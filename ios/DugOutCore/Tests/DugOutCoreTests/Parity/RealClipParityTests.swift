import XCTest
@testable import DugOutCore
@testable import ProbeOutput

/// The gate on real footage: Swift and the app's own JS, fed the same decoded frames and the same
/// Vision poses, must find the same swings and give the same marks. Skips without DUGOUT_CLIPS,
/// fails if it is set wrong (see RealClipTests).
final class RealClipParityTests: XCTestCase {
    func testPitch01SwiftAndJSAgreeExactly() async throws {
        guard let dir = ProcessInfo.processInfo.environment["DUGOUT_CLIPS"], !dir.isEmpty else {
            throw XCTSkip("DUGOUT_CLIPS is not set — real-footage parity skipped.")
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("pitch_01.mov")
        guard FileManager.default.fileExists(atPath: url.path) else { return XCTFail("pitch_01.mov not in DUGOUT_CLIPS") }
        let r = try await ParityRunner.run(url)
        XCTAssertTrue(r.segmentationIdentical, "segmentation differs at \(r.segmentationDiffAt ?? "?")")
        XCTAssertGreaterThan(r.native.swings.count, 0, "parity on zero swings proves nothing")
        for s in r.swings { XCTAssertTrue(s.analysisIdentical, "swing \(s.index + 1) differs at \(s.analysisDiffAt ?? "?")") }
        XCTAssertEqual(r.checkpointMatches, r.checkpointTotal)
        XCTAssertTrue(r.roundIdentical)
    }
}
