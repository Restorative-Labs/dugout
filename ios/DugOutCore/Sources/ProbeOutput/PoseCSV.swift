import DugOutCore
import Foundation

/// Per-frame pose as CSV — a TEST OUTPUT ONLY.
///
/// Pose keypoints are biometric data of a minor (CANON R-13, R-30): this never goes to a log, the
/// console, the repo, or anything that leaves the Mac. It lives in the ProbeOutput target, which
/// the app does not link, so the shipped binary contains no code that writes keypoints to disk.
public enum PoseCSV {
    public static var header: String {
        (["t", "people"] + TrackedJoint.allCases.flatMap { j in
            ["\(j.rawValue)_conf", "\(j.rawValue)_x", "\(j.rawValue)_y"]
        }).joined(separator: ",")
    }

    public static func row(_ frame: PoseFrame) -> String {
        var cells = [String(format: "%.6f", frame.t), String(frame.people)]
        for joint in TrackedJoint.allCases {
            let r = frame.joints[joint]
            cells.append(String(format: "%.6f", r?.confidence ?? 0))
            // A missing joint gets empty cells, never a fake (0, 0) position.
            cells.append(r?.x.map { String(format: "%.6f", $0) } ?? "")
            cells.append(r?.y.map { String(format: "%.6f", $0) } ?? "")
        }
        return cells.joined(separator: ",")
    }

    public static func write(_ frames: [PoseFrame], to url: URL) throws {
        let text = ([header] + frames.map(row)).joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
