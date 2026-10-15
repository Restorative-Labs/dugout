import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

/// The joints Phase 1 measures. CT-05 and CT-06 are defined on elbow-vs-wrist geometry, which
/// is why wrists and elbows are the ones that decide whether Vision is good enough.
/// Left/right are the subject's own left and right, as Vision labels them.
public enum TrackedJoint: String, CaseIterable {
    case leftWrist = "left_wrist", rightWrist = "right_wrist"
    case leftElbow = "left_elbow", rightElbow = "right_elbow"
    case leftShoulder = "left_shoulder", rightShoulder = "right_shoulder"
    case leftHip = "left_hip", rightHip = "right_hip"

    var visionName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .leftWrist: return .leftWrist
        case .rightWrist: return .rightWrist
        case .leftElbow: return .leftElbow
        case .rightElbow: return .rightElbow
        case .leftShoulder: return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftHip: return .leftHip
        case .rightHip: return .rightHip
        }
    }
}

public struct JointReading: Equatable {
    /// Vision's confidence, 0...1. Not the same scale as MoveNet's score — see docs/NATIVE-P1.md.
    public var confidence: Double
    /// Position as a fraction of the upright picture, Vision's convention: (0,0) is the
    /// BOTTOM-left corner, (1,1) the top-right. Nil when the joint was not found.
    public var x: Double?
    public var y: Double?

    public init(confidence: Double, x: Double?, y: Double?) {
        self.confidence = confidence
        self.x = x
        self.y = y
    }
}

/// One frame's result: how many people Vision saw, and the tracked joints of the one chosen as
/// the hitter. A joint Vision did not find is simply absent.
public struct PoseFrame: Equatable {
    public var t: Double
    public var people: Int
    public var joints: [TrackedJoint: JointReading]

    public init(t: Double, people: Int, joints: [TrackedJoint: JointReading]) {
        self.t = t
        self.people = people
        self.joints = joints
    }

    /// 0 when the joint (or the whole person) was not found — a miss counts against the model,
    /// the same way MoveNet's single-pose output reports a low score rather than nothing.
    public func confidence(_ joint: TrackedJoint) -> Double { joints[joint]?.confidence ?? 0 }
}

/// Runs Apple's body-pose model on one frame at a time.
///
/// The whole decoded frame goes in, at full resolution and correctly oriented. Vision scales it to
/// its own network input internally — that is not something this code controls or crops around.
/// No crop-and-rerun: if Vision needs that hack too, that is a finding for CANON, not code.
public final class BodyPoseDetector {
    private let orientation: CGImagePropertyOrientation
    // One request object, reused for every frame: Vision overwrites `results` on each perform.
    private let request = VNDetectHumanBodyPoseRequest()

    public init(orientation: CGImagePropertyOrientation) {
        self.orientation = orientation
    }

    /// Which version of Apple's model ran. Recorded so a later run on a newer OS can be told apart.
    public var revision: Int { request.revision }

    public func detect(_ frame: CVPixelBuffer, at t: Double) throws -> PoseFrame {
        // A handler wraps one image; `perform` runs the request on it synchronously.
        let handler = VNImageRequestHandler(cvPixelBuffer: frame, orientation: orientation, options: [:])
        try handler.perform([request])
        let people = request.results ?? []
        guard let subject = Self.pickSubject(people) else {
            return PoseFrame(t: t, people: 0, joints: [:])
        }
        let points = try subject.recognizedPoints(.all)
        var joints: [TrackedJoint: JointReading] = [:]
        for joint in TrackedJoint.allCases {
            guard let p = points[joint.visionName], p.confidence > 0 else { continue }
            joints[joint] = JointReading(confidence: Double(p.confidence),
                                         x: Double(p.location.x), y: Double(p.location.y))
        }
        return PoseFrame(t: t, people: people.count, joints: joints)
    }

    /// With more than one person in frame, take the one whose found joints span the largest area.
    /// Chosen by size, not by confidence, so the choice cannot flatter the confidence numbers.
    /// The test footage has one person in frame (docs/POSE-PROBE.md); frames with more are
    /// counted in the report so this rule's reach is visible.
    static func pickSubject(_ people: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        guard people.count > 1 else { return people.first }
        func area(_ o: VNHumanBodyPoseObservation) -> Double {
            guard let pts = try? o.recognizedPoints(.all).values.filter({ $0.confidence > 0.1 }),
                  !pts.isEmpty else { return 0 }
            let xs = pts.map { Double($0.location.x) }, ys = pts.map { Double($0.location.y) }
            return (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
        }
        return people.max { area($0) < area($1) }
    }
}

/// Pose for every frame of a clip.
public struct PoseRun {
    public let info: VideoTrackInfo
    public let modelRevision: Int
    public let frames: [PoseFrame]
    /// Decoded samples that were not footage and so never reached Vision.
    public let skipped: FrameReadReport

    public static func run(_ url: URL, upTo: Double? = nil,
                           progress: ((Double) -> Void)? = nil) async throws -> PoseRun {
        let reader = try await FrameReader.open(url)
        let detector = BodyPoseDetector(orientation: reader.info.orientation)
        var frames: [PoseFrame] = []
        frames.reserveCapacity(Int(reader.info.duration * max(reader.info.nominalFPS, 1)) + 1)
        let skipped = try reader.forEachFrame(upTo: upTo) { t, frame in
            frames.append(try detector.detect(frame, at: t))
            progress?(t)
        }
        return PoseRun(info: reader.info, modelRevision: detector.revision, frames: frames, skipped: skipped)
    }
}
