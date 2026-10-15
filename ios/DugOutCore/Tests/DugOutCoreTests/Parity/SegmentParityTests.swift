import XCTest
@testable import DugOutCore
@testable import ProbeOutput

/// P1.3 parity: every piece of js/segment.js, Swift vs the real JS, on IDENTICAL inputs.
/// Identical inputs is the point — this proves the port, separately from any difference in how
/// a browser and AVFoundation decode or scale the video (that is measured end-to-end elsewhere).
final class SegmentParityTests: XCTestCase {
    var js: JSReference!

    override func setUpWithError() throws { js = try JSReference() }

    // MARK: constants

    func testEveryPortedConstantEqualsConfigJS() throws {
        let cfg = try XCTUnwrap(try js.json("window.DUGOUT_CONFIG") as? [String: Any])
        for (key, value) in Tuning.portedConstants {
            XCTAssertNotNil(cfg[key], "\(key) is not in config.js")
            if let d = jsonDifference(value, cfg[key], at: key, tolerance: 0) { XCTFail(d) }
        }
    }

    // MARK: building blocks

    func testDiffEnergyAndMedianSmooth() throws {
        var rng = SeededRandom(seed: 1)
        for trial in 0..<20 {
            let n = Tuning.motionW * Tuning.motionH
            let a = (0..<n).map { _ in Float(rng.int(0, 255)) }
            let b = a.map { v in rng.chance(0.2) ? Float(rng.int(0, 255)) : v }
            js.setFloat32("__a", a); js.setFloat32("__b", b)
            let expected = try XCTUnwrap(try js.json("DugoutSegment.diffEnergy(__a, __b)") as? Double)
            XCTAssertEqual(SegmentMath.diffEnergy(a, b), expected, accuracy: 1e-12, "trial \(trial)")

            let vals = (0..<rng.int(1, 60)).map { _ in rng.range(0, 3) }
            let win = [1, 3, 5, 7, 9][rng.int(0, 4)]
            try js.set("__v", json: vals)
            let jsSm = try js.json("DugoutSegment.medianSmooth(__v, \(win))")
            if let d = jsonDifference(SegmentMath.medianSmooth(vals, win), jsSm) { XCTFail("trial \(trial): \(d)") }
        }
    }

    func testBallBlobsOnSyntheticFrames() throws {
        var rng = SeededRandom(seed: 2)
        let w = Tuning.ballW, h = Tuning.ballH
        for trial in 0..<12 {
            var prev = (0..<(w * h)).map { _ in UInt8(rng.int(60, 140)) }
            var cur = prev.map { v in UInt8(clamping: Int(v) + rng.int(-20, 20)) }   // shimmer below delta
            // a handful of ball-sized blobs, a big "hitter" blob and some streaks
            for _ in 0..<rng.int(2, 9) {
                let cx = rng.int(4, w - 5), cy = rng.int(4, h - 5)
                let rx = rng.int(0, 4), ry = rng.int(0, 4)
                for y in max(0, cy - ry)...min(h - 1, cy + ry) {
                    for x in max(0, cx - rx)...min(w - 1, cx + rx) { cur[y * w + x] = 250 }
                }
            }
            for y in 100..<(100 + rng.int(5, 30)) { for x in 200..<(200 + rng.int(5, 30)) { cur[y * w + x] = 10 } }
            if trial % 3 == 0 { prev = prev.map { 255 &- $0 } }   // a frame where everything changed
            js.setBytes("__cur", cur); js.setBytes("__prev", prev)
            let expected = try js.json("DugoutSegment.ballBlobs(__cur, __prev)")
            let got = try jsonObject(SegmentMath.ballBlobs(cur: cur, prev: prev))
            if let d = jsonDifference(got, expected) { XCTFail("trial \(trial): \(d)") }
        }
    }

    func testLinkBallTracks() throws {
        var rng = SeededRandom(seed: 3)
        var tracksSeen = 0
        defer { XCTAssertGreaterThan(tracksSeen, 8, "too few trials produced a real ball track") }
        for trial in 0..<40 {
            var frames: [BallFrame] = []
            var t = 0.0
            // a few straight fast balls, plus jittering noise blobs
            var balls = (0..<rng.int(0, 3)).map { _ in (x: rng.range(0, 480), y: rng.range(0, 270), vx: rng.range(-40, 40), vy: rng.range(-20, 20)) }
            for _ in 0..<rng.int(5, 60) {
                t += [1.0 / 30, 1.0 / 60, 0.1, 0.3][rng.int(0, 3)]
                var blobs: [BallBlob] = []
                for i in balls.indices {
                    balls[i].x += balls[i].vx; balls[i].y += balls[i].vy
                    if rng.chance(0.85) { blobs.append(BallBlob(x: balls[i].x, y: balls[i].y, area: rng.int(4, 40))) }
                }
                for _ in 0..<rng.int(0, 6) { blobs.append(BallBlob(x: rng.range(0, 480), y: rng.range(0, 270), area: rng.int(4, 140))) }
                frames.append(BallFrame(t: t, blobs: blobs))
            }
            try js.set("__frames", json: try jsonObject(frames))
            let expected = try js.json("DugoutSegment.linkBallTracks(__frames)")
            if ((expected as? [Any])?.count ?? 0) > 0 { tracksSeen += 1 }
            if let d = jsonDifference(try jsonObject(SegmentMath.linkBallTracks(frames)), expected) { XCTFail("trial \(trial): \(d)") }
        }
    }

    func testAudioPeaks() throws {
        var rng = SeededRandom(seed: 4)
        for trial in 0..<8 {
            let rate = [44100.0, 48000.0][trial % 2]
            let seconds = rng.range(2, 12)
            var samples = (0..<Int(rate * seconds)).map { _ in Float(rng.range(-0.01, 0.01)) }
            for _ in 0..<rng.int(0, 6) {   // contact-like clicks
                let at = Int(rng.range(0.1, seconds - 0.1) * rate)
                for k in 0..<Int(rate * 0.02) where at + k < samples.count {
                    samples[at + k] = Float(rng.range(-0.9, 0.9)) * Float(1 - Double(k) / (rate * 0.02))
                }
            }
            js.setFloat32("__samples", samples)
            js.ctx.evaluateScript("window.__audio = { samples: __samples, rate: \(rate) };")
            let expected = try js.json("DugoutSegment.audioPeaks(new Blob([]))")
            let got = SegmentMath.audioPeaks(samples: samples, sampleRate: rate)
            if let d = jsonDifference(got, expected) { XCTFail("trial \(trial): \(d)") }
        }
    }

    func testFindSwings() throws {
        var rng = SeededRandom(seed: 5)
        var withSwings = 0, multi = 0
        for trial in 0..<300 {
            let fps = [7.5, 15.0, 30.0, 60.0][rng.int(0, 3)]
            let duration = rng.range(0, 40)
            let count = trial % 25 == 0 ? rng.int(0, 9) : Int(duration * fps)   // some tiny inputs too
            let base = rng.chance(0.1) ? 0 : rng.range(0.005, 0.08)             // sometimes a dead-flat baseline
            // swing-shaped bursts: a fast rise over 0.1-0.6 s, 1.5-15x baseline (some camera-handling sized)
            let bursts = (0..<rng.int(0, 6)).map { _ in (at: rng.range(0, max(duration, 0.1)), len: rng.range(0.05, 0.6),
                                                          mult: rng.range(1.5, 15)) }
            var samples: [MotionSample] = []
            for i in 0..<count {
                let t = Double(i) / fps + (rng.chance(0.05) ? 0 : rng.range(0, 0.002))
                var e = max(0, base * rng.range(0.6, 1.4))
                for b in bursts where t >= b.at && t <= b.at + b.len {
                    e += max(base, 0.01) * b.mult * sin((t - b.at) / b.len * .pi)
                }
                samples.append(MotionSample(t: t, e: e))
            }
            // confirmation signals: near some bursts, plus strays
            var peaks: [Double] = []
            var tracks: [BallTrack] = []
            for b in bursts {
                if rng.chance(0.5) { peaks.append(b.at + b.len * rng.range(0, 2) + rng.range(-1, 1)) }
                if rng.chance(0.4) { let e = b.at + rng.range(-1, 1.5); tracks.append(BallTrack(startT: e - 0.3, endT: e, points: rng.int(3, 12))) }
            }
            for _ in 0..<rng.int(0, 2) { peaks.append(rng.range(0, max(duration, 0.1))) }
            peaks.sort()
            try js.set("__s", json: try jsonObject(samples))
            try js.set("__p", json: peaks)
            try js.set("__tr", json: try jsonObject(tracks))
            let expected = try js.json("DugoutSegment.findSwings(__s, __p, __tr)")
            let got = try jsonObject(SegmentMath.findSwings(samples: samples, peaks: peaks, ballTracks: tracks))
            if let d = jsonDifference(got, expected) { XCTFail("trial \(trial) (seed 5): \(d)") }
            let n = (expected as? [Any])?.count ?? 0
            if n > 0 { withSwings += 1 }; if n > 1 { multi += 1 }
        }
        // a parity test that never sees a swing proves nothing
        XCTAssertGreaterThan(withSwings, 50, "too few trials produced any swing")
        XCTAssertGreaterThan(multi, 20, "too few trials produced several swings")
    }
}
