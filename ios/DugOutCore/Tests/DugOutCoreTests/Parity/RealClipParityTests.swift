import XCTest
@testable import DugOutCore
@testable import ProbeOutput

/// The gate on real footage: Swift and the app's own JS, fed the same decoded frames and the same
/// Vision poses, must find the same swings (and the same samples, audio peaks, ball tracks and
/// capHit) and give the same analyses, marks, round and focus — on every regression clip.
/// Skips without DUGOUT_CLIPS, fails if it is set wrong (see RealClipTests).
final class RealClipParityTests: XCTestCase {
    static let clips = ["Three Swings.mov", "pitch_01.mov", "pitch_02.mov", "pitch_03.mov",
                        "pitch_04.mov", "pitch_05.mov", "pitch_06.mov"]

    func testAllRegressionClipsSwiftAndJSAgreeExactly() async throws {
        guard let dir = ProcessInfo.processInfo.environment["DUGOUT_CLIPS"], !dir.isEmpty else {
            throw XCTSkip("DUGOUT_CLIPS is not set — real-footage parity skipped.")
        }
        var graded = 0
        for name in Self.clips {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { XCTFail("\(name) not in DUGOUT_CLIPS"); continue }
            let r = try await ParityRunner.run(url)
            XCTAssertTrue(r.segmentationIdentical, "\(name): segmentation differs at \(r.segmentationDiffAt ?? "?")")
            XCTAssertGreaterThan(r.native.swings.count, 0, "\(name): parity on zero swings proves nothing")
            for s in r.swings {
                XCTAssertTrue(s.analysisIdentical, "\(name) swing \(s.index + 1) differs at \(s.analysisDiffAt ?? "?")")
                XCTAssertEqual(s.checkpointMatches, 6, "\(name) swing \(s.index + 1): marks differ")
            }
            XCTAssertTrue(r.roundIdentical, "\(name): round differs")
            XCTAssertTrue(r.focusIdentical, "\(name): focus differs")
            graded += r.gradedMatches
        }
        // agreement about nothing proves nothing: most marks must actually be graded
        XCTAssertGreaterThan(graded, 60, "too few graded marks — the comparison is mostly '—' on both sides")
    }
}
