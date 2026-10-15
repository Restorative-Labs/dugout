import Foundation

// js/evaluate.js, ported line for line (P1.4): pose track → geometry → the fifteen measurable
// fault detectors → per-swing faults → per-checkpoint PASS/FAIL → priority focus.
//
// Honesty rules carried over unchanged: a fault whose library entry has `detector: null` is never
// guessed at; ER-03 never names a fault seen in one swing; internal scores never leave this module
// (R-02) — they are `internal`, so app code cannot even read them.
//
// JavaScript semantics that change answers are reproduced deliberately and marked "JS:".
// EvaluateParityTests runs this and the real evaluate.js on identical tracks.

// MARK: - results

/// One detector's call on one swing: how strongly it sees the fault. Internal (R-02).
struct FaultReading: Codable, Equatable {
    var conf: Double
    var lowConfidence: Bool
}

public struct Orientation: Codable, Equatable {
    /// +1 or −1: which way along x the pitcher is.
    public var dir: Double
    public var frontIsLeft: Bool
    public var weak: Bool
}

public struct SwingAnalysis: Codable, Equatable {
    public var ok: Bool
    /// Why a swing could not be analysed: "no-pose", "no-orientation", "no-scale".
    public var reason: String?
    var faults: [String: FaultReading]
    public var orientation: Orientation?
    var contactU: Double?
    public var trackLength: Int?

    /// Tip ids this swing showed (detector at or above FAULT_PRESENT) — what the film viewer flags.
    public var faultIds: [String] {
        faults.filter { $0.value.conf >= Evaluator.faultPresent }.map(\.key).sorted()
    }

    enum CodingKeys: String, CodingKey { case ok, reason, faults, orientation, contactU, trackLength }
}

public struct IdentifiedAnalysis {
    public var swingId: String
    public var analysis: SwingAnalysis
    public init(swingId: String, analysis: SwingAnalysis) { self.swingId = swingId; self.analysis = analysis }
}

/// The coach's philosophy as far as grading is concerned (selection only — R-05).
public struct Philosophy: Codable, Equatable {
    public var tipSelections: [String: [String]]
    public var priorities: [String]
    public var redLineTipIds: [String]
    public init(tipSelections: [String: [String]], priorities: [String], redLineTipIds: [String]) {
        self.tipSelections = tipSelections; self.priorities = priorities; self.redLineTipIds = redLineTipIds
    }
    /// store.js activePhilosophy() default: every tip in play, checkpoint order, no red lines.
    public static let `default` = Philosophy(tipSelections: [:], priorities: Tuning.checkpoints, redLineTipIds: [])
}

/// PASS/FAIL for one checkpoint. `internalScore` is internal by design — never rendered (R-02).
public struct CheckpointMark: Codable, Equatable {
    public var pass: Bool
    /// false when nothing measurable existed for this checkpoint — show "not measured", not PASS.
    public var assessed: Bool
    var internalScore: Double?
    public var faultIds: [String]
    public var evidenceSwingIds: [String]

    enum CodingKeys: String, CodingKey { case pass, assessed, internalScore, faultIds, evidenceSwingIds }

    // internalScore is always present in the JS object (null when unassessed); keep the same shape
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pass, forKey: .pass)
        try c.encode(assessed, forKey: .assessed)
        try c.encode(internalScore, forKey: .internalScore)
        try c.encode(faultIds, forKey: .faultIds)
        try c.encode(evidenceSwingIds, forKey: .evidenceSwingIds)
    }
}

// MARK: - JS arithmetic helpers

/// Math.min / Math.max propagate NaN; Swift's min/max do not. Detector outputs that are NaN are
/// dropped by analyzeSwing (as in JS), so this has to stay NaN rather than become 0 or 1.
@inline(__always) func jsMin(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : Swift.min(a, b) }
@inline(__always) func jsMax(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : Swift.max(a, b) }
@inline(__always) func clamp01(_ v: Double) -> Double { jsMax(0, jsMin(1, v)) }
@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
/// 0 below lo, 1 above hi. JS: `(hi - lo || 1)` — a zero span divides by 1.
@inline(__always) func ramp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    let span = hi - lo
    return clamp01((v - lo) / (span != 0 ? span : 1))
}
@inline(__always) func jsSign(_ v: Double) -> Double { v > 0 ? 1 : (v < 0 ? -1 : v) }

// MARK: - evaluator

public enum Evaluator {
    /// A detector at or above this is calling the fault on that swing.
    static let faultPresent = 0.5

    struct Sample { var t: Double; var u: Double; var pose: Pose }

    struct Geom {
        var ls, rs, lh, rh, la, ra, lw, rw, le, re, lk, rk, nose: Point?
        var shoMid, hipMid, ankMid, wristMid: Point?
        var scale: Double?
        var hipSep, shoSep: Double?
    }

    struct Peak {
        var rate: Double
        var t: Double?
        var u: Double?
        /// JS: `null` in arithmetic is 0 — rotPeak.u is null when the signal never moved.
        var uOrZero: Double { u ?? 0 }
    }

    struct Context {
        var track: [Sample]
        var o: Orientation
        var scale: Double
        var rotPeak: Peak?
        var shoPeak: Peak?
        var contactU: Double
    }

    struct DetectorResult { var conf: Double; var lowConfidence = false }

    // ---------- pose track (evaluate.js buildTrack) ----------
    static func buildTrack(_ frames: [KeyframePose]) -> [Sample]? {
        let step = max(1, frames.count / Tuning.poseSamplesPerSwing)
        var track: [Sample] = []
        for i in stride(from: 0, to: frames.count, by: step) {
            if let pose = frames[i].pose { track.append(Sample(t: frames[i].t, u: 0, pose: pose)) }
        }
        if track.isEmpty { return nil }
        let t0 = track[0].t, t1 = track[track.count - 1].t
        for i in track.indices { track[i].u = t1 > t0 ? (track[i].t - t0) / (t1 - t0) : 0 }
        return track
    }

    // ---------- geometry (evaluate.js geom) ----------
    static func geom(_ s: Sample) -> Geom {
        let p = s.pose
        var g = Geom()
        g.ls = p.ok("left_shoulder"); g.rs = p.ok("right_shoulder")
        g.lh = p.ok("left_hip"); g.rh = p.ok("right_hip")
        g.la = p.ok("left_ankle"); g.ra = p.ok("right_ankle")
        g.lw = p.ok("left_wrist"); g.rw = p.ok("right_wrist")
        g.le = p.ok("left_elbow"); g.re = p.ok("right_elbow")
        g.lk = p.ok("left_knee"); g.rk = p.ok("right_knee")
        g.nose = p.ok("nose")
        g.shoMid = mid(g.ls, g.rs); g.hipMid = mid(g.lh, g.rh); g.ankMid = mid(g.la, g.ra)
        if let s = g.shoMid, let h = g.hipMid { g.scale = max(1, dist(s, h)) }   // torso length, ≥ 1 px
        if let lh = g.lh, let rh = g.rh { g.hipSep = rh.x - lh.x }
        if let ls = g.ls, let rs = g.rs { g.shoSep = rs.x - ls.x }
        g.wristMid = mid(g.lw, g.rw)
        return g
    }

    // ---------- orientation (evaluate.js orient) ----------
    static func orient(_ track: [Sample]) -> Orientation? {
        let first = geom(track[0])
        let mids = track.map(geom).filter { $0.la != nil && $0.ra != nil }
        if mids.isEmpty || first.scale == nil { return nil }
        let a0 = mids[0]
        let aN = mids[Int((Double(mids.count) * 0.7).rounded(.down))]   // index < count, never undefined
        let dL = aN.la!.x - a0.la!.x, dR = aN.ra!.x - a0.ra!.x
        let frontIsLeft = abs(dL) >= abs(dR)
        let d = frontIsLeft ? dL : dR
        if abs(d) < 1 { return Orientation(dir: 1, frontIsLeft: frontIsLeft, weak: true) }
        return Orientation(dir: jsSign(d), frontIsLeft: frontIsLeft, weak: false)
    }

    /// evaluate.js at(): the sample nearest u (first one on a tie).
    static func at(_ track: [Sample], _ u: Double) -> Sample {
        var best = track[0], bd = 1e9
        for s in track { let d = abs(s.u - u); if d < bd { bd = d; best = s } }
        return best
    }

    static func between(_ track: [Sample], _ u0: Double, _ u1: Double) -> [Sample] {
        track.filter { $0.u >= u0 && $0.u <= u1 }
    }

    static func series(_ track: [Sample], _ pick: (Geom) -> Double?) -> [(u: Double, t: Double, v: Double)] {
        track.compactMap { s in
            guard let v = pick(geom(s)), !v.isNaN else { return nil }
            return (s.u, s.t, v)
        }
    }

    static func maxDeriv(_ sig: [(u: Double, t: Double, v: Double)]) -> Peak {
        var best = Peak(rate: 0, t: nil, u: nil)
        for i in 1..<sig.count {
            let dt = sig[i].t - sig[i - 1].t
            if dt <= 0 { continue }
            let r = abs(sig[i].v - sig[i - 1].v) / dt
            if r > best.rate { best = Peak(rate: r, t: sig[i].t, u: sig[i].u) }
        }
        return best
    }

    // ---------- detectors (evaluate.js DETECTORS) ----------
    // Each returns the fault confidence, or nil when the swing does not have the joints for it.
    static let detectors: [String: (Context) -> DetectorResult?] = [
        "stance.baseWidth": { ctx in
            let g = geom(at(ctx.track, 0.05))
            guard let la = g.la, let ra = g.ra, let ls = g.ls, let rs = g.rs else { return nil }
            let ank = abs(ra.x - la.x), sho = abs(rs.x - ls.x)
            if sho < 1 { return nil }
            let ratio = ank / sho
            let conf = ratio < 1.0 ? ramp(1.0 - ratio, 0.05, 0.5) : ramp(ratio - 1.9, 0.05, 0.8)
            return DetectorResult(conf: conf)
        },
        "stance.weightBias": { ctx in
            let g = geom(at(ctx.track, 0.05))
            guard let hip = g.hipMid, let la = g.la, let ra = g.ra, g.scale != nil else { return nil }
            let back = ctx.o.dir > 0 ? min(la.x, ra.x) : max(la.x, ra.x)
            let front = ctx.o.dir > 0 ? max(la.x, ra.x) : min(la.x, ra.x)
            let span = front - back
            if abs(span) < 1 { return nil }
            let pos = (hip.x - back) / span
            return DetectorResult(conf: ramp(pos - 0.5, 0.02, 0.35))
        },
        "load.noLoad": { ctx in
            let seg = between(ctx.track, Tuning.phaseWindows["load"]![0], Tuning.phaseWindows["load"]![1]).map(geom)
            if seg.count < 2 { return nil }
            let hips = seg.compactMap(\.hipMid)
            if hips.count < 2 { return nil }
            let travel = hips.map(\.x).max()! - hips.map(\.x).min()!
            let norm = travel / ctx.scale
            return DetectorResult(conf: 1 - ramp(norm, 0.02, 0.14))
        },
        "load.drift": { ctx in
            let a = geom(at(ctx.track, 0.08)), b = geom(at(ctx.track, Tuning.contactAnchor))
            guard let h0 = a.nose ?? a.shoMid, let h1 = b.nose ?? b.shoMid else { return nil }
            let drift = (h1.x - h0.x) * ctx.o.dir / ctx.scale
            return DetectorResult(conf: ramp(drift, 0.12, 0.55))
        },
        "stride.overstride": { ctx in
            let s0 = geom(at(ctx.track, 0.05)), s1 = geom(at(ctx.track, Tuning.contactAnchor))
            guard let la0 = s0.la, let ra0 = s0.ra, let la1 = s1.la, let ra1 = s1.ra else { return nil }
            let base = abs(ra0.x - la0.x), land = abs(ra1.x - la1.x)
            if base < 1 { return nil }
            let growth = land / base
            let spanNorm = land / ctx.scale
            return DetectorResult(conf: jsMax(ramp(growth, 1.7, 2.6), ramp(spanNorm, 2.1, 3.2)))
        },
        "stride.bucket": { ctx in
            // weak from a side view; capped so it can never become a priority focus alone
            let s0 = geom(at(ctx.track, 0.05)), s1 = geom(at(ctx.track, Tuning.contactAnchor))
            guard let f0 = ctx.o.frontIsLeft ? s0.la : s0.ra, let f1 = ctx.o.frontIsLeft ? s1.la : s1.ra else { return nil }
            let lateral = abs(f1.y - f0.y) / ctx.scale
            return DetectorResult(conf: jsMin(0.55, ramp(lateral, 0.25, 0.8)), lowConfidence: true)
        },
        "stride.headMove": { ctx in
            let seg = between(ctx.track, 0.05, Tuning.contactAnchor).map(geom).filter { $0.nose != nil || $0.shoMid != nil }
            if seg.count < 3 { return nil }
            let pts = seg.map { $0.nose ?? $0.shoMid! }
            let dx = pts.map(\.x).max()! - pts.map(\.x).min()!
            let dy = pts.map(\.y).max()! - pts.map(\.y).min()!
            return DetectorResult(conf: ramp(hypot(dx, dy) / ctx.scale, 0.25, 0.85))
        },
        "stride.early": { ctx in
            guard let rot = ctx.rotPeak else { return nil }
            return DetectorResult(conf: ramp(ctx.contactU - rot.uOrZero, 0.10, 0.30))
        },
        "stride.late": { ctx in
            guard let rot = ctx.rotPeak else { return nil }
            return DetectorResult(conf: ramp(rot.uOrZero - ctx.contactU, 0.04, 0.22))
        },
        "hips.rotationSpeed": { ctx in
            guard let rot = ctx.rotPeak else { return nil }
            return DetectorResult(conf: 1 - ramp(rot.rate / ctx.scale, 1.2, 5.0))
        },
        "hips.separation": { ctx in
            guard let rot = ctx.rotPeak, let sho = ctx.shoPeak else { return nil }
            return DetectorResult(conf: 1 - ramp(sho.uOrZero - rot.uOrZero, 0.005, 0.09))
        },
        "hips.flyOpen": { ctx in
            guard let rot = ctx.rotPeak, let sho = ctx.shoPeak else { return nil }
            return DetectorResult(conf: ramp(rot.uOrZero - sho.uOrZero, 0.01, 0.14))
        },
        "hips.backsideCollapse": { ctx in
            let g = geom(at(ctx.track, Tuning.contactAnchor))
            let s = geom(at(ctx.track, 0.05))
            guard let gs = g.shoMid, let gh = g.hipMid, let ss = s.shoMid, let sh = s.hipMid else { return nil }
            let tilt0 = (ss.x - sh.x) * ctx.o.dir / ctx.scale
            let tilt1 = (gs.x - gh.x) * ctx.o.dir / ctx.scale
            let drop = (gh.y - sh.y) / ctx.scale
            return DetectorResult(conf: jsMax(ramp(tilt0 - tilt1, 0.18, 0.6), ramp(drop, 0.12, 0.45)))
        },
        "contact.casting": { ctx in
            // rear elbow gets outside the hands early in the turn (Hemond's detection rule)
            let g = geom(at(ctx.track, lerp(Tuning.phaseWindows["hips"]![0], Tuning.contactAnchor, 0.4)))
            guard let elbow = ctx.o.frontIsLeft ? g.re : g.le, let wrist = ctx.o.frontIsLeft ? g.rw : g.lw else { return nil }
            let outside = (wrist.x - elbow.x) * ctx.o.dir / ctx.scale
            return DetectorResult(conf: 1 - ramp(outside, -0.05, 0.35))
        },
        "contact.batDrag": { ctx in
            // rear elbow in front of the hands during the turn
            let g = geom(at(ctx.track, lerp(Tuning.phaseWindows["hips"]![0], Tuning.contactAnchor, 0.7)))
            guard let elbow = ctx.o.frontIsLeft ? g.re : g.le, let wrist = ctx.o.frontIsLeft ? g.rw : g.lw else { return nil }
            let ahead = (elbow.x - wrist.x) * ctx.o.dir / ctx.scale
            return DetectorResult(conf: ramp(ahead, 0.05, 0.4))
        },
        "contact.headPull": { ctx in
            let g0 = geom(at(ctx.track, lerp(Tuning.phaseWindows["stride"]![0], Tuning.contactAnchor, 0.5)))
            let g1 = geom(at(ctx.track, Tuning.contactAnchor))
            guard let n0 = g0.nose, let n1 = g1.nose, let s0 = g0.shoMid, let s1 = g1.shoMid else { return nil }
            let rel0 = (n0.x - s0.x) * ctx.o.dir / ctx.scale
            let rel1 = (n1.x - s1.x) * ctx.o.dir / ctx.scale
            return DetectorResult(conf: ramp(rel0 - rel1, 0.1, 0.5))
        },
        "finish.balance": { ctx in
            let seg = between(ctx.track, Tuning.phaseWindows["finish"]![0], 1).map(geom).filter { $0.ankMid != nil && $0.hipMid != nil }
            if seg.count < 2 { return nil }
            let hipSway = seg.map { abs($0.hipMid!.x - $0.ankMid!.x) }.max()! / ctx.scale
            let footShift = (seg.map { $0.ankMid!.x }.max()! - seg.map { $0.ankMid!.x }.min()!) / ctx.scale
            return DetectorResult(conf: jsMax(ramp(hipSway, 0.55, 1.4), ramp(footShift, 0.2, 0.7)))
        },
        "finish.height": { ctx in
            // hands proxy for the barrel; NB wristMid falls back to ONE wrist (CANON R-42)
            let seg = between(ctx.track, Tuning.phaseWindows["finish"]![0], 1).map(geom).filter { $0.wristMid != nil && $0.shoMid != nil }
            if seg.isEmpty { return nil }
            let best = seg.map { $0.wristMid!.y - $0.shoMid!.y }.min()! / ctx.scale
            return DetectorResult(conf: ramp(best, 0.15, 0.85))
        },
    ]

    // ---------- per swing (evaluate.js analyzeSwing) ----------
    public static func analyzeSwing(frames: [KeyframePose], contactT: Double?, library: TipLibrary) -> SwingAnalysis {
        guard let track = buildTrack(frames), track.count >= 4 else {
            return SwingAnalysis(ok: false, reason: "no-pose", faults: [:])
        }
        guard let o = orient(track) else { return SwingAnalysis(ok: false, reason: "no-orientation", faults: [:]) }
        let scales = track.map(geom).compactMap(\.scale).sorted()
        guard !scales.isEmpty else { return SwingAnalysis(ok: false, reason: "no-scale", faults: [:]) }
        let scale = scales[scales.count / 2]

        let hipSig = series(track) { $0.hipSep }
        let shoSig = series(track) { $0.shoSep }
        let rotPeak = hipSig.count > 2 ? maxDeriv(hipSig) : nil
        let shoPeak = shoSig.count > 2 ? maxDeriv(shoSig) : nil

        let t0 = track[0].t, t1 = track[track.count - 1].t
        let contactU = (contactT != nil && t1 > t0) ? clamp01((contactT! - t0) / (t1 - t0)) : Tuning.contactAnchor

        let ctx = Context(track: track, o: o, scale: scale, rotPeak: rotPeak, shoPeak: shoPeak, contactU: contactU)
        var faults: [String: FaultReading] = [:]
        for tip in library.tips {
            guard let name = tip.detector, !tip.isToggle, let fn = detectors[name] else { continue }   // never guessed at
            if let r = fn(ctx), !r.conf.isNaN {
                faults[tip.id] = FaultReading(conf: clamp01(r.conf), lowConfidence: r.lowConfidence)
            }
        }
        return SwingAnalysis(ok: true, reason: nil, faults: faults, orientation: o, contactU: contactU, trackLength: track.count)
    }

    // ---------- round (evaluate.js rollup) ----------
    public static func rollup(_ swingResults: [IdentifiedAnalysis], ageBand band: String,
                              philosophy: Philosophy, library: TipLibrary) -> [String: CheckpointMark] {
        let good = swingResults.filter { $0.analysis.ok }
        let n = good.count
        var perCheckpoint: [String: CheckpointMark] = [:]
        for cp in Tuning.checkpoints {
            let tips = library.tips.filter { t in
                t.checkpoint == cp && t.detector != nil && !t.isToggle &&
                    t.ageBands.contains(band) && !philosophy.redLineTipIds.contains(t.id) &&
                    selected(philosophy, cp, t.id)
            }
            var faultIds: [String] = []
            var evidence: [(String, [String])] = []      // JS object: insertion order
            var cleanliness: [Double] = []
            for tip in tips {
                let seen = good.filter { $0.analysis.faults[tip.id] != nil }
                if seen.isEmpty { continue }
                let hits = seen.filter { $0.analysis.faults[tip.id]!.conf >= faultPresent }
                // ER-03: never name a fault from a single swing
                let enough = hits.count >= Tuning.minFaultSwings ||
                    (n > 0 && Double(hits.count) / Double(n) >= Tuning.minFaultShare && hits.count >= 2)
                if !hits.isEmpty && enough {
                    faultIds.append(tip.id)
                    evidence.append((tip.id, hits.map(\.swingId)))
                }
                let cleanShare = seen.reduce(0.0) { $0 + (1 - $1.analysis.faults[tip.id]!.conf) } / Double(seen.count)
                cleanliness.append(cleanShare)
            }
            let internalScore: Double? = cleanliness.isEmpty ? nil : cleanliness.reduce(0, +) / Double(cleanliness.count)
            let thrRaw = Tuning.passThresholds[cp] ?? 0
            let thr = thrRaw != 0 ? thrRaw : Tuning.passThresholdDefault        // JS: `|| DEFAULT`
            var evidenceIds: [String] = []
            for id in evidence.flatMap(\.1) where !evidenceIds.contains(id) { evidenceIds.append(id) }
            perCheckpoint[cp] = CheckpointMark(
                pass: internalScore.map { $0 >= thr } ?? true,
                assessed: internalScore != nil,
                internalScore: internalScore,
                faultIds: faultIds,
                evidenceSwingIds: evidenceIds)
        }
        return perCheckpoint
    }

    static func selected(_ phi: Philosophy, _ cp: String, _ tipId: String) -> Bool {
        guard let sel = phi.tipSelections[cp], !sel.isEmpty else { return true }
        return sel.contains(tipId)
    }

    /// A single swing graded on its own — "a single swing is a round of one" (DUG-34). This is how
    /// per-swing PASS/FAIL marks are defined; the JS app only ever graded whole rounds.
    public static func marksForSwing(_ analysis: SwingAnalysis, ageBand: String, philosophy: Philosophy,
                                     library: TipLibrary) -> [String: CheckpointMark] {
        rollup([IdentifiedAnalysis(swingId: "swing", analysis: analysis)], ageBand: ageBand,
               philosophy: philosophy, library: library)
    }

    // ---------- priority focus (evaluate.js priorityFocus) ----------
    /// The lowest-scoring failing checkpoint; within 0.02 of each other, the philosophy's order wins.
    public static func priorityFocus(_ marks: [String: CheckpointMark], philosophy: Philosophy) -> String? {
        var fails = Tuning.checkpoints.filter { marks[$0].map { $0.assessed && !$0.pass } ?? false }
        if fails.isEmpty { return nil }
        let order = philosophy.priorities.isEmpty ? Tuning.checkpoints : philosophy.priorities
        func index(_ cp: String) -> Double { Double(order.firstIndex(of: cp) ?? -1) }
        // The comparator is not a strict weak order (a 0.02 tolerance, then a fallback), so the
        // result depends on the sort algorithm. Reproduce JavaScriptCore's — the engine the app
        // ran in on the phone.
        jscSort(&fails) { a, b in
            let d = marks[a]!.internalScore! - marks[b]!.internalScore!
            if abs(d) > 0.02 { return d }
            return index(a) - index(b)
        }
        return fails[0]
    }

    /// JavaScriptCore's Array.prototype.sort with a comparator, for short arrays (verified up to
    /// 20 elements): binary insertion sort. Each next element is compared with the middle of the sorted prefix as
    /// comparator(element, middle) and goes left only when the result is negative (stable on ties).
    /// Established by recording JSC's comparator call order; TipLibrary-independent test
    /// EvaluateParityTests.testSortMatchesJavaScriptCoreCallForCall pins it.
    static func jscSort<T>(_ array: inout [T], _ comparator: (T, T) -> Double) {
        guard array.count > 1 else { return }
        // From 8 elements up, JSC first extends the already-ascending prefix (comparing each
        // element with its predecessor) and binary-inserts only what follows. priorityFocus never
        // sorts more than 6 checkpoints; this branch is here so the port is faithful anyway.
        var start = 1
        if array.count >= 8 {
            while start < array.count && comparator(array[start], array[start - 1]) >= 0 { start += 1 }
        }
        for i in start..<array.count {
            let x = array[i]
            var lo = 0, hi = i
            while lo < hi {
                let mid = (lo + hi) >> 1
                if comparator(x, array[mid]) < 0 { hi = mid } else { lo = mid + 1 }
            }
            if lo < i {
                array.remove(at: i)
                array.insert(x, at: lo)
            }
        }
    }
}
