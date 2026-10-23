import Foundation

// The decision logic of js/segment.js, ported line for line (P1.3). Nothing here touches video:
// it takes the numbers the sampler measured and decides where the swings are. Each function says
// which JS function it mirrors; SegmentParityTests runs both on the same inputs and demands the
// same answer. Where JavaScript has a quirk (`x || 0.001` turning a zero into a fallback,
// Math.round rounding halves up), the quirk is reproduced on purpose and commented.

public struct MotionSample: Codable, Equatable {
    public var t: Double      // presentation time of the later frame of the pair, seconds
    public var e: Double      // mean above-threshold luma change between the two frames
    public init(t: Double, e: Double) { self.t = t; self.e = e }
}

public struct BallBlob: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var area: Int
    public init(x: Double, y: Double, area: Int) { self.x = x; self.y = y; self.area = area }
}

public struct BallFrame: Codable, Equatable {
    public var t: Double
    public var blobs: [BallBlob]
    public init(t: Double, blobs: [BallBlob]) { self.t = t; self.blobs = blobs }
}

public struct BallTrack: Codable, Equatable {
    public var startT: Double
    public var endT: Double
    public var points: Int
    public init(startT: Double, endT: Double, points: Int) { self.startT = startT; self.endT = endT; self.points = points }
}

/// One swing window: padded start/end, the contact moment, whether a contact sound confirmed it.
public struct SwingSpan: Equatable {
    public var start: Double
    public var end: Double
    public var contactT: Double
    public var audioConfirmed: Bool
    /// Peak motion over baseline. Internal — never shown to a user.
    var confidence: Double

    enum CodingKeys: String, CodingKey { case start, end, contactT, audioConfirmed, confidence }
}

public enum SegmentMath {

    /// segment.js diffEnergy(): mean of the per-pixel luma changes that exceed MOTION_PIXEL_DELTA.
    public static func diffEnergy(_ a: [Float], _ b: [Float]) -> Double {
        var acc = 0.0
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                for i in 0..<pa.count {
                    let df = abs(Double(pa[i]) - Double(pb[i]))
                    if df > Tuning.motionPixelDelta { acc += df }
                }
            }
        }
        return acc / Double(a.count)
    }

    /// segment.js medianSmooth(): running median over a centred window, clipped at the ends.
    public static func medianSmooth(_ vals: [Double], _ win: Int) -> [Double] {
        let half = win / 2
        return vals.indices.map { i in
            let window = vals[max(0, i - half)..<min(vals.count, i + half + 1)].sorted()
            return window[window.count / 2]
        }
    }

    /// segment.js ballBlobs(): connected components (8-neighbour) of the pixels whose luma changed
    /// by more than BALL_PIXEL_DELTA, kept if ball-sized and not a long streak. Scan order and
    /// neighbour order match the JS, so blobs come out in the same order.
    public static func ballBlobs(cur: [UInt8], prev: [UInt8]) -> [BallBlob] {
        let w = Tuning.ballW, h = Tuning.ballH, n = w * h
        let delta = Int(Tuning.ballPixelDelta)
        precondition(cur.count == n && prev.count == n, "ball frames must be \(w)×\(h)")
        var seen = [UInt8](repeating: 0, count: n)
        var stack = [Int32](repeating: 0, count: n)
        var out: [BallBlob] = []
        cur.withUnsafeBufferPointer { c in
            prev.withUnsafeBufferPointer { p in
                @inline(__always) func changed(_ i: Int) -> Bool { abs(Int(c[i]) - Int(p[i])) > delta }
                for p0 in 0..<n {
                    if seen[p0] != 0 { continue }
                    if !changed(p0) { seen[p0] = 1; continue }
                    var sp = 0
                    stack[sp] = Int32(p0); sp += 1; seen[p0] = 1
                    var count = 0, sx = 0, sy = 0
                    var x0 = Int.max, x1 = -1, y0 = Int.max, y1 = -1
                    while sp > 0 {
                        sp -= 1
                        let q = Int(stack[sp])
                        let qx = q % w, qy = q / w
                        count += 1; sx += qx; sy += qy
                        if qx < x0 { x0 = qx }; if qx > x1 { x1 = qx }
                        if qy < y0 { y0 = qy }; if qy > y1 { y1 = qy }
                        for dy in -1...1 {
                            for dx in -1...1 {
                                let nx = qx + dx, ny = qy + dy
                                if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
                                let r = ny * w + nx
                                if seen[r] != 0 { continue }
                                if !changed(r) { seen[r] = 1; continue }
                                seen[r] = 1
                                if sp < n { stack[sp] = Int32(r); sp += 1 }
                            }
                        }
                    }
                    if count < Tuning.ballMinArea || count > Tuning.ballMaxArea { continue }
                    let bw = Double(x1 - x0 + 1), bh = Double(y1 - y0 + 1)
                    if max(bw / bh, bh / bw) > Tuning.ballMaxAspect { continue }   // an arm or a bat
                    out.append(BallBlob(x: Double(sx) / Double(count), y: Double(sy) / Double(count), area: count))
                }
            }
        }
        return out
    }

    /// segment.js linkBallTracks(): greedily chain blobs into trajectories, then keep only the
    /// ones that persist, travel far, fly straight and fast — a ball, not a leaf.
    public static func linkBallTracks(_ frames: [BallFrame]) -> [BallTrack] {
        struct Pt { var x: Double; var y: Double; var t: Double }
        struct Track { var pts: [Pt]; var closed: Bool }
        var tracks: [Track] = []
        for f in frames {
            for b in f.blobs {
                var best: Int? = nil
                var bd = Tuning.ballMaxJump
                for i in tracks.indices {
                    if tracks[i].closed { continue }
                    let last = tracks[i].pts[tracks[i].pts.count - 1]
                    if f.t - last.t > 0.25 { tracks[i].closed = true; continue }
                    if f.t == last.t { continue }
                    let d = hypot(b.x - last.x, b.y - last.y)
                    if d < bd { bd = d; best = i }
                }
                if let best { tracks[best].pts.append(Pt(x: b.x, y: b.y, t: f.t)) }
                else { tracks.append(Track(pts: [Pt(x: b.x, y: b.y, t: f.t)], closed: false)) }
            }
        }
        return tracks.compactMap { tr in
            if tr.pts.count < Tuning.ballMinTrack { return nil }
            let a = tr.pts[0], z = tr.pts[tr.pts.count - 1]
            let net = hypot(z.x - a.x, z.y - a.y)
            if net < Tuning.ballMinDisp { return nil }
            var path = 0.0
            for i in 1..<tr.pts.count { path += hypot(tr.pts[i].x - tr.pts[i - 1].x, tr.pts[i].y - tr.pts[i - 1].y) }
            if path <= 0 || net / path < Tuning.ballMinStraight { return nil }
            let dt = z.t - a.t
            if dt <= 0 || net / dt < Tuning.ballMinSpeed { return nil }
            return BallTrack(startT: a.t, endT: z.t, points: tr.pts.count)
        }
    }

    /// segment.js audioPeaks() after decoding: a 10 ms RMS envelope of channel 0, and the local
    /// maxima above max(6 × median, 0.45 × 99.5th percentile), at least 0.25 s apart.
    public static func audioPeaks(samples ch: [Float], sampleRate sr: Double) -> [Double] {
        let win = Int((sr * 0.01).rounded(.down))
        guard win > 0 else { return [] }
        var env: [Double] = []
        ch.withUnsafeBufferPointer { c in
            var i = 0
            while i + win < c.count {
                var s = 0.0
                for j in 0..<win { let v = Double(c[i + j]); s += v * v }
                env.append((s / Double(win)).squareRoot())
                i += win
            }
        }
        let sorted = env.sorted()
        // JS: `sorted[k] || 0` — an empty envelope reads as 0
        let med = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let hiIndex = Int((Double(sorted.count) * 0.995).rounded(.down))
        let hi = hiIndex < sorted.count ? sorted[hiIndex] : 0
        let thr = max(med * 6, hi * 0.45)
        var peaks: [Double] = []
        if env.count >= 3 {
            for i in 1..<(env.count - 1) where env[i] > thr && env[i] >= env[i - 1] && env[i] > env[i + 1] {
                let t = Double(i) * 0.01
                if peaks.isEmpty || t - peaks[peaks.count - 1] > 0.25 { peaks.append(t) }
            }
        }
        return peaks
    }

    /// JavaScript's Math.round: halves round toward +∞ (Swift's .rounded() rounds them away from 0).
    @inline(__always) static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    /// segment.js findSwings(): smooth, threshold with hysteresis, merge, filter, gate, then map
    /// each span to a padded swing window with a contact time.
    public static func findSwings(samples: [MotionSample], peaks audio: [Double], ballTracks tracks: [BallTrack]) -> [SwingSpan] {
        if samples.count < 4 { return [] }
        let raw = samples.map(\.e)

        // Smoothing window from the measured sample cadence, so it spans ~MOTION_SMOOTH_SEC.
        var win = Tuning.motionSmoothWin
        if Tuning.motionSmoothSec > 0 && samples.count > 8 {
            let dts = (1..<samples.count).map { samples[$0].t - samples[$0 - 1].t }.sorted()
            let mdtRaw = dts[dts.count / 2]
            let mdt = mdtRaw != 0 ? mdtRaw : 0.033                    // JS: `|| 0.033`
            let w = jsRound(Tuning.motionSmoothSec / mdt)
            var wi = w.isFinite ? Int(min(max(w, -1e9), 1e9)) : 9
            if wi % 2 == 0 { wi += 1 }                                 // median wants an odd window
            win = max(3, min(9, wi))
        }
        let sm = medianSmooth(raw, win)
        let sortedSm = sm.sorted()
        let baselineRaw = sortedSm[Int((Double(sortedSm.count) * 0.5).rounded(.down))]
        let baseline = baselineRaw != 0 ? baselineRaw : 0.001          // JS: `|| 0.001`
        let enter = max(baseline * Tuning.spikeEnterMult, 0.02)
        let exit = max(baseline * Tuning.spikeExitMult, 0.01)

        struct Span { var start: Double; var end: Double; var peakT: Double; var peakE: Double }
        var spans: [Span] = []
        var inS = false
        var st = 0.0, peakE = 0.0, peakT = 0.0
        for i in sm.indices {
            let t = samples[i].t
            if !inS && sm[i] > enter { inS = true; st = t; peakE = sm[i]; peakT = t }
            else if inS {
                if sm[i] > peakE { peakE = sm[i]; peakT = t }
                if sm[i] < exit { inS = false; spans.append(Span(start: st, end: t, peakT: peakT, peakE: peakE)) }
            }
        }
        if inS { spans.append(Span(start: st, end: samples[samples.count - 1].t, peakT: peakT, peakE: peakE)) }

        // merge spans that are really one swing (load and follow-through can dip between)
        var merged: [Span] = []
        for s in spans {
            if var last = merged.last, s.start - last.end < Tuning.minGapSec {
                last.end = s.end
                if s.peakE > last.peakE { last.peakE = s.peakE; last.peakT = s.peakT }
                merged[merged.count - 1] = last
            } else { merged.append(s) }
        }

        let gateSec = Tuning.gateAudioSec != 0 ? Tuning.gateAudioSec : Tuning.audioConfirmSec
        return merged
            .filter { $0.end - $0.start >= Tuning.minSwingSec }
            // camera handling is not a swing
            .filter { Tuning.maxSpikeMult == 0 || $0.peakE <= baseline * Tuning.maxSpikeMult }
            // the gate, v2: an arriving ball OR a contact sound; with neither signal anywhere, motion only
            .filter { s in
                if tracks.isEmpty && audio.isEmpty { return true }
                let ballNear = tracks.contains { tr in
                    abs(tr.endT - s.peakT) <= Tuning.ballNearSec ||
                        (s.start - Tuning.ballNearSec <= tr.endT && tr.endT <= s.end + Tuning.ballNearSec)
                }
                let audioNear = audio.contains { p in
                    abs(p - s.peakT) <= gateSec || (s.start - 0.4 <= p && p <= s.end + 0.5)
                }
                return ballNear || audioNear
            }
            .map { s in
                // audio only sharpens contact; its absence never disqualifies a swing (whiffs count)
                let near = audio.filter { abs($0 - s.peakT) <= Tuning.audioConfirmSec }
                var contactT = s.peakT
                if var best = near.first {
                    for b in near.dropFirst() where abs(b - s.peakT) < abs(best - s.peakT) { best = b }
                    contactT = best
                }
                var start = s.start, end = s.end
                if Tuning.swingTightenSec > 0 && end - start > Tuning.swingTightenSec {
                    let pre = Tuning.swingTightenSec * (Tuning.contactAnchor != 0 ? Tuning.contactAnchor : 0.62)
                    let post = Tuning.swingTightenSec - pre
                    start = max(start, contactT - pre)
                    end = min(end, contactT + post)
                }
                return SwingSpan(start: max(0, start - Tuning.prePadSec), end: end + Tuning.postPadSec,
                                 contactT: contactT, audioConfirmed: !near.isEmpty,
                                 confidence: s.peakE / max(baseline, 0.001))
            }
    }

    /// segment.js segment(), the caps step: 90 s OR 15 swings, whichever comes first.
    /// segment()'s decision, from linking the ball tracks through the caps: link, the saturation
    /// guard, findSwings, then the 90 s / 15-swing caps. Segmenter calls exactly this; the parity
    /// tests hold it to the JS's own lines for the same steps (JSReference.installSegmentTail).
    public static func decide(samples: [MotionSample], ballFrames: [BallFrame], peaks: [Double], durationSec: Double)
        -> (swings: [SwingSpan], capHit: String?, tracks: [BallTrack], saturated: Bool) {
        var tracks = linkBallTracks(ballFrames)
        let saturated = tracks.count > Tuning.ballMaxTracks
        if saturated { tracks = [] }   // a gate that matches everything is worse than no gate
        let capped = applyCaps(findSwings(samples: samples, peaks: peaks, ballTracks: tracks), durationSec: durationSec)
        return (capped.swings, capped.capHit, tracks, saturated)
    }

    public static func applyCaps(_ swings: [SwingSpan], durationSec: Double) -> (swings: [SwingSpan], capHit: String?) {
        var out = swings
        var capHit: String? = nil
        if durationSec > Tuning.capSeconds {
            out = out.filter { $0.start < Tuning.capSeconds }
            for i in out.indices { out[i].end = min(out[i].end, Tuning.capSeconds) }
            capHit = "time"   // JS sets it whenever the clip is over the cap
        }
        if out.count > Tuning.capSwings {
            out = Array(out.prefix(Tuning.capSwings))
            capHit = "swings"
        }
        return (out, capHit)
    }
}
