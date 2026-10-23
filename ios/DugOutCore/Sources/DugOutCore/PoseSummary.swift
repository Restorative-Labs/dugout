import Foundation

public struct ConfidenceSummary {
    /// Frames in the window.
    public let frames: Int
    /// Values pooled: frames × joints (a "both wrists" summary has two values per frame).
    public let values: Int
    /// Values where the joint was found at all (confidence > 0).
    public let found: Int
    public let median: Double
    public let p10: Double
    public let mean: Double
}

public enum PoseSummary {
    /// Confidence distribution for one or more joints, optionally only for frames whose time
    /// falls in `window`. Misses count as 0. Returns nil when no frame falls in the window.
    public static func summarize(_ frames: [PoseFrame], joints: [TrackedJoint],
                                 in window: ClosedRange<Double>? = nil) -> ConfidenceSummary? {
        let picked = window.map { w in frames.filter { w.contains($0.t) } } ?? frames
        guard !picked.isEmpty, !joints.isEmpty else { return nil }
        let values = picked.flatMap { f in joints.map { f.confidence($0) } }
        return ConfidenceSummary(frames: picked.count,
                                 values: values.count,
                                 found: values.filter { $0 > 0 }.count,
                                 median: Stats.median(values)!,
                                 p10: Stats.percentile(values, 10)!,
                                 mean: Stats.mean(values)!)
    }

    public static func summarize(_ frames: [PoseFrame], joint: TrackedJoint,
                                 in window: ClosedRange<Double>? = nil) -> ConfidenceSummary? {
        summarize(frames, joints: [joint], in: window)
    }
}
