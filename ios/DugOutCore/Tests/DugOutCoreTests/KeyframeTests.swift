import AVFoundation
import XCTest
@testable import DugOutCore

/// Keyframes must be the frame ON SCREEN at each time — the last frame presented at or before t —
/// which is what segment.js got by seeking a <video>. No keyframe may silently go missing.
final class KeyframeTests: XCTestCase {

    private func check(codec: AVVideoCodecType, name: String) async throws {
        // 30 fps with a gap: a frame on screen spans until the next one arrives
        let ticks: [Int64] = (0..<40).map { Int64($0) * 20 } + (0..<40).map { 1200 + Int64($0) * 20 }
        let url = SyntheticClip.tempURL(name)
        try SyntheticClip.write(to: url, width: 320, height: 180, ticks: ticks, codec: codec)
        let info = try await FrameReader.open(url).info
        var rng = SeededRandom(seed: 21)
        let times = ((0..<24).map { _ in rng.range(0, Double(ticks.last!) / 600) } + [0, 0.0001, 1.95, 2.0]).sorted()
        let s = try await KeyframePoser.sample(url, info: info, times: times)
        let pts = ticks.map { Double($0) / 600 }
        for (t, got) in zip(times, s.sourcePTS) {
            let expected = pts.last(where: { $0 <= t + 1e-9 }) ?? pts[0]
            XCTAssertNotNil(got, "\(name): no frame for t=\(t)")
            if let got { XCTAssertEqual(got, expected, accuracy: 1e-6, "\(name): t=\(t)") }
        }
    }

    func testOnScreenFrameH264() async throws { try await check(codec: .h264, name: "kf-h264") }
    func testOnScreenFrameHEVC() async throws { try await check(codec: .hevc, name: "kf-hevc") }

    /// A frame with nobody in it has NO pose — not an all-zero one. The vendored MoveNet returns no
    /// pose when its pose score is under 0.25, pose.js then returns null, and buildTrack skips the
    /// frame. An all-zero pose would instead sit in the track: at keyframe 0 it makes orient() fail
    /// the whole swing, elsewhere it shifts `u` and drops detectors.
    func testEmptyFrameHasNoPose() async throws {
        let url = SyntheticClip.tempURL("kf-empty")
        try SyntheticClip.write(to: url, width: 320, height: 180, ticks: (0..<30).map { Int64($0) * 20 })
        let info = try await FrameReader.open(url).info
        let s = try await KeyframePoser.sample(url, info: info, times: [0, 0.5, 0.9])
        XCTAssertEqual(s.sourcePTS.compactMap { $0 }.count, 3, "every keyframe was decoded")
        for kf in s.poses { XCTAssertTrue(kf.pose == nil, "t=\(kf.t): an empty frame must give no pose, as pose.js does") }  // never print a pose
        // and a swing whose every frame is empty is "no-pose", as buildTrack's empty track is
        let a = Evaluator.analyzeSwing(frames: s.poses, contactT: 0.5, library: try TipLibrary.bundled())
        XCTAssertFalse(a.ok)
        XCTAssertEqual(a.reason, "no-pose")
    }

    /// The real HEVC pitch clips: every one of the 24 keyframes of every swing must be a decoded frame.
    func testPitch01NoKeyframeGoesMissing() async throws {
        guard let dir = ProcessInfo.processInfo.environment["DUGOUT_CLIPS"], !dir.isEmpty else {
            throw XCTSkip("DUGOUT_CLIPS is not set — real-footage keyframe test skipped.")
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("pitch_01.mov")
        guard FileManager.default.fileExists(atPath: url.path) else { return XCTFail("pitch_01.mov not in DUGOUT_CLIPS") }
        let seg = try await Segmenter.segment(url)
        XCTAssertFalse(seg.swings.isEmpty)
        for span in seg.swings {
            let s = try await KeyframePoser.sample(url, info: seg.info, times: KeyframePoser.times(for: span, duration: seg.durationSec))
            XCTAssertEqual(s.sourcePTS.compactMap { $0 }.count, Tuning.keyframesPerSwing, "keyframes missing in swing at \(span.contactT)")
        }
    }
}
