import Foundation

/// A 2-D pose in the shape js/pose.js uses: named keypoints, pixel coordinates of the keyframe
/// image (540 wide, y pointing DOWN), and a 0…1 score. Keeping MoveNet's names and pixel space
/// means every threshold in the evaluator keeps meaning exactly what it meant in JS — a few of
/// them are in pixels (`< 1`), not in torso-lengths.
public struct Keypoint: Codable, Equatable {
    public var name: String
    public var x: Double
    public var y: Double
    public var score: Double
    public init(name: String, x: Double, y: Double, score: Double) {
        self.name = name; self.x = x; self.y = y; self.score = score
    }
}

public struct Pose: Codable, Equatable {
    public var keypoints: [Keypoint]
    public init(keypoints: [Keypoint]) { self.keypoints = keypoints }

    /// The 17 MoveNet names, in MoveNet's order.
    public static let jointNames = [
        "nose", "left_eye", "right_eye", "left_ear", "right_ear", "left_shoulder", "right_shoulder",
        "left_elbow", "right_elbow", "left_wrist", "right_wrist", "left_hip", "right_hip",
        "left_knee", "right_knee", "left_ankle", "right_ankle",
    ]

    /// pose.js ok(): the joint if it was found with score ≥ POSE_MIN_SCORE, else nil.
    func ok(_ name: String) -> Point? {
        guard let k = keypoints.first(where: { $0.name == name }), k.score >= Tuning.poseMinScore else { return nil }
        return Point(x: k.x, y: k.y)
    }
}

struct Point: Equatable {
    var x: Double
    var y: Double
}

/// pose.js mid(): the midpoint of two joints — or, if only one was found, that one. (This quiet
/// fallback is why FN-03 still renders when the lead wrist drops: CANON R-42.)
func mid(_ a: Point?, _ b: Point?) -> Point? {
    if let a, let b { return Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    return a ?? b
}

/// pose.js dist().
func dist(_ a: Point, _ b: Point) -> Double { hypot(a.x - b.x, a.y - b.y) }

/// A pose at one keyframe time, or nil when no person was found there.
public struct KeyframePose {
    public var t: Double
    public var pose: Pose?
    public init(t: Double, pose: Pose?) { self.t = t; self.pose = pose }
}
