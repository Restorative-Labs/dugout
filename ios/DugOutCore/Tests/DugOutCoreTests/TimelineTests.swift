import CoreGraphics
import ImageIO
import XCTest
@testable import DugOutCore

/// P1.1 — the frame timeline is trustworthy. Checked against clips whose timestamps we wrote.
final class TimelineTests: XCTestCase {

    /// 30 fps for one second, then a 0.2 s hole, then 30 fps again. The reader must report the
    /// real times — including the hole — not times re-spaced to the nominal rate.
    func testReadsRealPresentationTimestampsIncludingAGap() async throws {
        let ticks: [Int64] = (0..<30).map { Int64($0) * 20 } + (0..<15).map { 720 + Int64($0) * 20 }
        let url = SyntheticClip.tempURL("gap")
        try SyntheticClip.write(to: url, ticks: ticks)

        let timeline = try await ClipTimeline.read(url)

        XCTAssertEqual(timeline.timestamps.count, ticks.count)
        for (got, tick) in zip(timeline.timestamps, ticks) {
            XCTAssertEqual(got, Double(tick) / 600, accuracy: 1e-6)
        }
        XCTAssertTrue(timeline.isMonotonic)
        XCTAssertEqual(timeline.medianDelta ?? 0, 1.0 / 30, accuracy: 1e-6)
        XCTAssertEqual(timeline.minDelta ?? 0, 1.0 / 30, accuracy: 1e-6)
        XCTAssertEqual(timeline.maxDelta ?? 0, 1.2 - 29.0 / 30, accuracy: 1e-6)
        // The one long delta is the hole between frame 29 (0.9667 s) and frame 30 (1.2 s).
        let odd = timeline.irregularDeltas()
        XCTAssertEqual(odd.count, 1)
        XCTAssertEqual(odd.first?.index, 30)
        XCTAssertEqual(odd.first?.delta ?? 0, 1.2 - 29.0 / 30, accuracy: 1e-6)
    }

    /// An iPhone clip starts with an empty edit. AVAssetReader fills it with one all-black frame at
    /// t=0 that no camera ever captured. It must be skipped and counted, not handed on as footage.
    func testEmptyEditFillerFrameIsSkippedAndCounted() async throws {
        let plain = SyntheticClip.tempURL("edit-src")
        try SyntheticClip.write(to: plain, ticks: (0..<10).map { Int64($0) * 20 })
        let edited = SyntheticClip.tempURL("edit")
        try SyntheticClip.withLeadingEmptyEdit(plain, emptyTicks: 113, to: edited)   // 0.1883 s, like pitch_01

        let timeline = try await ClipTimeline.read(edited)

        XCTAssertEqual(timeline.timestamps.count, 10)
        XCTAssertEqual(timeline.timestamps.first ?? -1, 113.0 / 600, accuracy: 1e-6)
        XCTAssertEqual(timeline.editFillerFrames, 1)
        XCTAssertEqual(timeline.info.emptyEdits.count, 1)
        XCTAssertEqual(timeline.info.emptyEdits.first?.upperBound ?? 0, 113.0 / 600, accuracy: 1e-6)
        XCTAssertTrue(timeline.irregularDeltas().isEmpty)   // the edit is not a dropped frame
    }

    func testReportsCodecResolutionAndOrientation() async throws {
        let url = SyntheticClip.tempURL("portrait")
        // A 90° rotation is how an iPhone marks a clip that was filmed holding the phone upright.
        try SyntheticClip.write(to: url, ticks: (0..<10).map { Int64($0) * 20 },
                                transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 90, ty: 0))

        let timeline = try await ClipTimeline.read(url)

        XCTAssertEqual(timeline.info.codec, "avc1")
        XCTAssertEqual(timeline.info.width, 160)
        XCTAssertEqual(timeline.info.height, 90)
        XCTAssertEqual(timeline.info.orientation, .right)
        XCTAssertEqual(timeline.info.nominalFPS, 30, accuracy: 0.5)
    }

    func testOrientationFromTrackTransform() {
        XCTAssertEqual(imageOrientation(for: .identity), .up)
        XCTAssertEqual(imageOrientation(for: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)), .right)
        XCTAssertEqual(imageOrientation(for: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)), .left)
        XCTAssertEqual(imageOrientation(for: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)), .down)
    }
}
