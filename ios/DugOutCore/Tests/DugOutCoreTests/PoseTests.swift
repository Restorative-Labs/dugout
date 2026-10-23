import XCTest
@testable import DugOutCore
@testable import ProbeOutput

/// P1.2 plumbing — every frame gets a row, nobody is invented, and the CSV shape is fixed.
/// Whether Vision actually sees the wrists is a question for the real clips (RealClipTests).
final class PoseTests: XCTestCase {

    func testEveryFrameGetsARowAndBlankFramesFindNobody() async throws {
        let ticks: [Int64] = (0..<12).map { Int64($0) * 20 }
        let url = SyntheticClip.tempURL("blank")
        try SyntheticClip.write(to: url, width: 320, height: 180, ticks: ticks)

        let run = try await PoseRun.run(url)

        XCTAssertEqual(run.frames.count, ticks.count)
        for (frame, tick) in zip(run.frames, ticks) {
            XCTAssertEqual(frame.t, Double(tick) / 600, accuracy: 1e-6)
            XCTAssertEqual(frame.people, 0)
            for joint in TrackedJoint.allCases {
                XCTAssertEqual(frame.confidence(joint), 0)
            }
        }
    }

    func testCSVHasOneColumnPerJointValueAndBlanksForMissingJoints() {
        // t, people, then confidence + x + y for each of the 8 tracked joints.
        let header = PoseCSV.header.split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(header.count, 2 + TrackedJoint.allCases.count * 3)
        XCTAssertEqual(header.first, "t")
        XCTAssertTrue(PoseCSV.header.contains("left_wrist_conf,left_wrist_x,left_wrist_y"))

        let frame = PoseFrame(t: 1.5, people: 1, joints: [
            .rightWrist: JointReading(confidence: 0.75, x: 0.25, y: 0.5),
        ])
        let row = PoseCSV.row(frame).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(row.count, header.count)
        XCTAssertEqual(row[0], "1.500000")
        XCTAssertEqual(row[1], "1")
        let rw = header.firstIndex(of: "right_wrist_conf")!
        // Six decimals, like t and x/y, so every reported median re-derives exactly from the CSV.
        XCTAssertEqual(row[rw], "0.750000")
        XCTAssertEqual(row[rw + 1], "0.250000")
        XCTAssertEqual(row[rw + 2], "0.500000")
        let lw = header.firstIndex(of: "left_wrist_conf")!
        XCTAssertEqual(row[lw], "0.000000") // not found → zero confidence…
        XCTAssertEqual(row[lw + 1], "")       // …and no position, rather than a fake 0,0
        XCTAssertEqual(row[lw + 2], "")
    }
}
