import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Keyframes and their poses — segment.js extractKeyframes + evaluate.js buildTrack's estimator,
/// with Apple Vision in place of MoveNet (one pass, no crop — CANON R-42).
public enum KeyframePoser {
    /// segment.js extractKeyframes(): KEYFRAMES_PER_SWING times spread evenly over the window.
    public static func times(for swing: SwingSpan, duration: Double) -> [Double] {
        let n = Tuning.keyframesPerSwing
        let end = min(swing.end, duration)
        return (0..<n).map { i in swing.start + (end - swing.start) * (Double(i) / Double(n - 1)) }
    }

    /// The keyframe image size the JS posed on: the upright video scaled to KEYFRAME_WIDTH wide.
    /// Poses are reported in these pixels so the evaluator's pixel-unit guards mean what they did.
    public static func keyframeSize(_ info: VideoTrackInfo) -> (w: Double, h: Double) {
        let quarterTurn = info.orientation == .right || info.orientation == .left
        let vw = Double(quarterTurn ? info.height : info.width)
        let vh = Double(quarterTurn ? info.width : info.height)
        let scale = min(1, Double(Tuning.keyframeWidth) / vw)
        return (SegmentMath.jsRound(vw * scale), SegmentMath.jsRound(vh * scale))
    }

    /// Vision joint → MoveNet name. Vision has no "neck"/"root" in MoveNet; those are unused.
    static let names: [(VNHumanBodyPoseObservation.JointName, String)] = [
        (.nose, "nose"), (.leftEye, "left_eye"), (.rightEye, "right_eye"), (.leftEar, "left_ear"),
        (.rightEar, "right_ear"), (.leftShoulder, "left_shoulder"), (.rightShoulder, "right_shoulder"),
        (.leftElbow, "left_elbow"), (.rightElbow, "right_elbow"), (.leftWrist, "left_wrist"),
        (.rightWrist, "right_wrist"), (.leftHip, "left_hip"), (.rightHip, "right_hip"),
        (.leftKnee, "left_knee"), (.rightKnee, "right_knee"), (.leftAnkle, "left_ankle"), (.rightAnkle, "right_ankle"),
    ]

    /// A pose with every joint unfound. MoveNet SinglePose always returns a pose (with low scores)
    /// even on an empty frame; Vision returns nothing. Recording this keeps the track the same
    /// length — and so the same time base `u` — as the JS.
    static var nobody: Pose { Pose(keypoints: Pose.jointNames.map { Keypoint(name: $0, x: 0, y: 0, score: 0) }) }

    static func pose(from cgImage: CGImage, size: (w: Double, h: Double)) throws -> Pose {
        let request = VNDetectHumanBodyPoseRequest()
        try VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:]).perform([request])
        guard let person = BodyPoseDetector.pickSubject(request.results ?? []),
              let points = try? person.recognizedPoints(.all) else { return nobody }
        return Pose(keypoints: names.map { vn, name in
            guard let p = points[vn], p.confidence > 0 else { return Keypoint(name: name, x: 0, y: 0, score: 0) }
            // Vision: normalised, origin bottom-left. Keyframe pixels: origin top-left, y down.
            return Keypoint(name: name, x: Double(p.location.x) * size.w, y: (1 - Double(p.location.y)) * size.h,
                            score: Double(p.confidence))
        })
    }

    /// Pose at each time, on the full-resolution upright frame shown at that moment.
    public static func poses(asset: AVAsset, info: VideoTrackInfo, times: [Double]) async throws -> [KeyframePose] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true          // upright, as the browser drew it
        generator.requestedTimeToleranceBefore = .zero           // the exact frame on screen at t
        generator.requestedTimeToleranceAfter = .zero
        let size = keyframeSize(info)
        var out: [KeyframePose] = []
        for t in times {
            let time = CMTime(seconds: max(0, min(info.duration, t)), preferredTimescale: 600)   // seekTo clamps
            var image: CGImage?
            if #available(iOS 16, macOS 13, *) {
                image = try? await generator.image(at: time).image
            } else {
                image = try? generator.copyCGImage(at: time, actualTime: nil)
            }
            // A frame the generator cannot produce (e.g. inside an empty edit) is "nobody there".
            let pose = try image.map { try Self.pose(from: $0, size: size) } ?? nobody
            out.append(KeyframePose(t: t, pose: pose))
        }
        return out
    }
}

/// One analysed swing.
public struct AnalyzedSwing {
    public let index: Int
    public let span: SwingSpan
    public let keyframes: [KeyframePose]
    public let analysis: SwingAnalysis
    /// This swing graded on its own, as a round of one (DUG-34). PASS/FAIL only is public.
    public let marks: [String: CheckpointMark]
}

public struct RoundResult {
    public let segmentation: SegmentationResult
    public let swings: [AnalyzedSwing]
    /// The whole clip graded as one round — what the JS app showed.
    public let roundMarks: [String: CheckpointMark]
    public let focus: String?
}

/// The whole pipeline: clip → swings → keyframe poses → six checkpoints. Nothing is saved, nothing
/// is logged, nothing leaves the device (R-13, R-30).
public enum RoundAnalyzer {
    public static func analyze(_ url: URL, ageBand: String = "11-13", philosophy: Philosophy = .default,
                               library: TipLibrary? = nil,
                               progress: ((_ stage: String, _ fraction: Double) -> Void)? = nil) async throws -> RoundResult {
        let library = try library ?? TipLibrary.bundled()
        let seg = try await Segmenter.segment(url) { progress?("Finding swings", $0 * 0.7) }
        let asset = AVURLAsset(url: url)
        var swings: [AnalyzedSwing] = []
        for (i, span) in seg.swings.enumerated() {
            progress?("Reading swing \(i + 1) of \(seg.swings.count)", 0.7 + 0.3 * Double(i) / Double(max(1, seg.swings.count)))
            let frames = try await KeyframePoser.poses(asset: asset, info: seg.info,
                                                       times: KeyframePoser.times(for: span, duration: seg.durationSec))
            let analysis = Evaluator.analyzeSwing(frames: frames, contactT: span.contactT, library: library)
            swings.append(AnalyzedSwing(index: i, span: span, keyframes: frames, analysis: analysis,
                                        marks: Evaluator.marksForSwing(analysis, ageBand: ageBand,
                                                                       philosophy: philosophy, library: library)))
        }
        let identified = swings.map { IdentifiedAnalysis(swingId: "swing-\($0.index)", analysis: $0.analysis) }
        let round = Evaluator.rollup(identified, ageBand: ageBand, philosophy: philosophy, library: library)
        progress?("Done", 1)
        return RoundResult(segmentation: seg, swings: swings, roundMarks: round,
                           focus: Evaluator.priorityFocus(round, philosophy: philosophy))
    }
}

/// Per-frame skeletons for drawing over the video (test screen). Normalised to the upright
/// picture with the origin at the TOP-left, ready for a view to scale.
public struct OverlayFrame {
    public let t: Double
    /// MoveNet joint name → (x, y, confidence). Missing joints are absent.
    public let joints: [String: (x: Double, y: Double, confidence: Double)]
}

public enum PoseOverlay {
    public static func frames(_ url: URL, from start: Double, to end: Double) async throws -> [OverlayFrame] {
        let reader = try await FrameReader.open(url)
        let request = VNDetectHumanBodyPoseRequest()
        var out: [OverlayFrame] = []
        try reader.forEachFrame(from: start, upTo: end) { t, frame in
            try VNImageRequestHandler(cvPixelBuffer: frame, orientation: reader.info.orientation, options: [:]).perform([request])
            var joints: [String: (x: Double, y: Double, confidence: Double)] = [:]
            if let person = BodyPoseDetector.pickSubject(request.results ?? []),
               let points = try? person.recognizedPoints(.all) {
                for (vn, name) in KeyframePoser.names {
                    if let p = points[vn], p.confidence > 0 {
                        joints[name] = (Double(p.location.x), 1 - Double(p.location.y), Double(p.confidence))
                    }
                }
            }
            out.append(OverlayFrame(t: t, joints: joints))
        }
        return out
    }
}
