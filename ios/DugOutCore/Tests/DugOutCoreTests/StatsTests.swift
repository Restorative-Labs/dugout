import XCTest
@testable import DugOutCore

final class StatsTests: XCTestCase {

    /// Linear interpolation between closest ranks — the same definition as numpy's default
    /// `percentile`, so anyone can re-check these numbers from the CSV in one line of Python.
    func testPercentileMatchesNumpyLinear() {
        XCTAssertEqual(Stats.percentile([3, 1, 2, 5, 4], 50), 3)
        XCTAssertEqual(Stats.percentile([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 10)!, 1, accuracy: 1e-12)
        XCTAssertEqual(Stats.percentile([1, 2, 3, 4], 50)!, 2.5, accuracy: 1e-12)
        XCTAssertEqual(Stats.percentile([10, 20], 10)!, 11, accuracy: 1e-12)
        XCTAssertEqual(Stats.percentile([7], 10), 7)
        XCTAssertNil(Stats.percentile([], 50))
    }

    func testSummaryCountsMissedFramesAsZeroAndRespectsTheWindow() {
        func f(_ t: Double, _ c: Double) -> PoseFrame {
            PoseFrame(t: t, people: c > 0 ? 1 : 0,
                      joints: c > 0 ? [.leftWrist: JointReading(confidence: c, x: 0.5, y: 0.5)] : [:])
        }
        let frames = [f(0.0, 0.9), f(0.1, 0.0), f(0.2, 0.5), f(0.3, 0.7), f(1.0, 0.1)]

        let all = PoseSummary.summarize(frames, joint: .leftWrist)!
        XCTAssertEqual(all.frames, 5)
        XCTAssertEqual(all.median, 0.5, accuracy: 1e-12)   // the miss counts as 0, not skipped
        XCTAssertEqual(all.found, 4)

        let near = PoseSummary.summarize(frames, joint: .leftWrist, in: 0.05...0.35)!
        XCTAssertEqual(near.frames, 3)
        XCTAssertEqual(near.median, 0.5, accuracy: 1e-12)
        XCTAssertNil(PoseSummary.summarize(frames, joint: .leftWrist, in: 5...6))
    }
}
