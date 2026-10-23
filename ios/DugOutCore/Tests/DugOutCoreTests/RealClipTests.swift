import XCTest
@testable import DugOutCore

/// Runs against the real test clips. They are footage of a real child and never enter the repo,
/// so these tests read them from wherever DUGOUT_CLIPS points and skip, loudly, when it is unset:
///
///     DUGOUT_CLIPS="$HOME/Library/CloudStorage/OneDrive2-RestorativeLabsLLC/Restorative Labs - Documents/04 — Dugout/Design & UX/media/test-clips" swift test
final class RealClipTests: XCTestCase {

    struct MissingClip: Error, CustomStringConvertible { let description: String }

    /// Unset → skip (a Mac without the footage). Set but wrong → FAIL: a typo or a renamed
    /// OneDrive folder must not turn into a quietly green suite.
    private func clip(_ name: String) throws -> URL {
        guard let dir = ProcessInfo.processInfo.environment["DUGOUT_CLIPS"], !dir.isEmpty else {
            throw XCTSkip("DUGOUT_CLIPS is not set — real-footage tests skipped. Point it at Design & UX/media/test-clips in the OneDrive workspace.")
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            let why = "DUGOUT_CLIPS is set but \(name) is not in it (\(dir))."
            XCTFail(why)
            throw MissingClip(description: why)
        }
        return url
    }

    /// The real pitch clips open with an iPhone empty edit; its black filler frame is not footage.
    func testPitch01FillerFrameIsNotCountedAsFootage() async throws {
        let timeline = try await ClipTimeline.read(try clip("pitch_01.mov"))

        XCTAssertEqual(timeline.editFillerFrames, 1)
        XCTAssertEqual(timeline.timestamps.first ?? 0, 0.188, accuracy: 1e-6)
        XCTAssertEqual(timeline.timestamps.count, 690)
    }

    /// P1.1 acceptance: monotonic timestamps, deltas consistent with the nominal frame rate.
    func testPitch01TimelineIsMonotonicAndMatchesNominalRate() async throws {
        let timeline = try await ClipTimeline.read(try clip("pitch_01.mov"))

        XCTAssertGreaterThan(timeline.timestamps.count, 100)
        XCTAssertTrue(timeline.isMonotonic)
        let nominal = 1 / timeline.info.nominalFPS
        XCTAssertEqual(timeline.medianDelta ?? 0, nominal, accuracy: nominal * 0.05)
    }

    /// Vision finds a person in most of the opening two seconds of pitch_01 (single subject in
    /// frame per docs/POSE-PROBE.md). This is plumbing, not the confidence verdict.
    func testPitch01OpeningSecondsHaveAPerson() async throws {
        let run = try await PoseRun.run(try clip("pitch_01.mov"), upTo: 2.0)

        XCTAssertGreaterThan(run.frames.count, 30)
        let withPerson = run.frames.filter { $0.people > 0 }.count
        XCTAssertGreaterThan(Double(withPerson) / Double(run.frames.count), 0.5)
    }
}
