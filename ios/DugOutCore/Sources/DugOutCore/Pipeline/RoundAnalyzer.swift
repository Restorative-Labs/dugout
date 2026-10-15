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

    /// Which decoded frame stood in for each keyframe time (its presentation time), or nil when no
    /// frame could be had. Internal: the tests check it; nothing displays it.
    struct Sampled { var poses: [KeyframePose]; var sourcePTS: [Double?] }

    /// Pose at each time, on the frame ON SCREEN at that moment: the last frame presented at or
    /// before t — what segment.js got by seeking a <video>.
    ///
    /// The swing window is decoded IN ORDER with AVAssetReader. (AVAssetImageGenerator at zero
    /// tolerance was used first and silently refused ~9% of keyframes on iPhone HEVC — the frames
    /// just before each sync frame, error -11821 — which became "nobody" poses. Found 2026-10-15.)
    static func sample(_ url: URL, info: VideoTrackInfo, times: [Double]) async throws -> Sampled {
        guard !times.isEmpty else { return Sampled(poses: [], sourcePTS: []) }
        let reader = try await FrameReader.open(url)
        let size = keyframeSize(info)
        let targets = times.map { max(0, min(info.duration, $0)) }             // seekTo clamps
        let order = targets.indices.sorted { targets[$0] < targets[$1] }
        var poses = [Pose?](repeating: nil, count: times.count)
        var pts = [Double?](repeating: nil, count: times.count)
        var next = 0                                     // next index into `order` still to assign
        var prev: (frame: CVPixelBuffer, t: Double)?

        /// Pose `frame` once and hand it to every pending target in `range` of `order`.
        func assign(_ frame: CVPixelBuffer, at t: Double, upTo end: Int) throws {
            guard next < end else { return }
            let pose = try Self.pose(from: frame, orientation: info.orientation, size: size)
            while next < end { poses[order[next]] = pose; pts[order[next]] = t; next += 1 }
        }

        // start a little early so the frame already on screen at the first target is decoded too
        try reader.forEachFrame(from: max(0, targets[order[0]] - 1.0), upTo: targets[order[order.count - 1]] + 1.0) { t, frame in
            // targets before this frame's time belong to the previous frame (or, before the very
            // first frame, to this one — a seek before the first frame shows the first frame)
            var end = next
            while end < order.count && targets[order[end]] < t - 1e-9 { end += 1 }
            if end > next { try assign(prev?.frame ?? frame, at: prev?.t ?? t, upTo: end) }
            prev = (frame, t)
        }
        if let prev { try assign(prev.frame, at: prev.t, upTo: order.count) }   // the rest: the last frame
        return Sampled(poses: times.indices.map { KeyframePose(t: times[$0], pose: poses[$0] ?? nobody) },
                       sourcePTS: pts)
    }

    static func pose(from frame: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                     size: (w: Double, h: Double)) throws -> Pose {
        let request = VNDetectHumanBodyPoseRequest()
        try VNImageRequestHandler(cvPixelBuffer: frame, orientation: orientation, options: [:]).perform([request])
        guard let person = BodyPoseDetector.pickSubject(request.results ?? []),
              let points = try? person.recognizedPoints(.all) else { return nobody }
        return Pose(keypoints: names.map { vn, name in
            guard let p = points[vn], p.confidence > 0 else { return Keypoint(name: name, x: 0, y: 0, score: 0) }
            // Vision: normalised to the upright picture, origin bottom-left. Keyframe pixels: y down.
            return Keypoint(name: name, x: Double(p.location.x) * size.w, y: (1 - Double(p.location.y)) * size.h,
                            score: Double(p.confidence))
        })
    }

    /// Pose at each keyframe time (see `sample`).
    public static func poses(_ url: URL, info: VideoTrackInfo, times: [Double]) async throws -> [KeyframePose] {
        try await sample(url, info: info, times: times).poses
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
        var swings: [AnalyzedSwing] = []
        for (i, span) in seg.swings.enumerated() {
            progress?("Reading swing \(i + 1) of \(seg.swings.count)", 0.7 + 0.3 * Double(i) / Double(max(1, seg.swings.count)))
            let frames = try await KeyframePoser.poses(url, info: seg.info,
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
