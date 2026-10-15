import AVFoundation
import DugOutCore
import Foundation
import JavaScriptCore

/// Decision-logic parity on a real clip — TEST TOOLING, never linked by the app.
///
/// One decode of the clip feeds BOTH implementations the same measurements:
///   * segmentation: every frame's upright motion/ball grids and the decoded audio go to the Swift
///     Segmenter and, identically, to the app's own segment.js functions running in JavaScriptCore
///     (diffEnergy, ballBlobs, linkBallTracks, audioPeaks, and segment()'s own guard/findSwings/caps
///     lines lifted out of the file — see JSReference.installSegmentTail);
///   * evaluation: the same Vision keyframe poses go to the Swift Evaluator and to evaluate.js's
///     real analyzeSwing / rollup / priorityFocus.
/// So any difference is a port bug. What this does NOT show is that native finds what the web app
/// finds on the phone: the browser samples ~1 frame in 4 (rVFC at 4×), computes luma from RGB on a
/// canvas, and poses with MoveNet. Those input differences change swing counts on some clips and are
/// measured separately (CANON R-44), not here.
///
/// Reports carry PASS/FAIL and counts only. Where two values differ, only the PATH of the
/// difference is reported — never an internal score (R-02).
public struct ClipParity: Codable {
    public struct Swing: Codable { public var start: Double; public var end: Double; public var contactT: Double; public var audioConfirmed: Bool }
    public struct Side: Codable {
        public var swings: [Swing]
        public var capHit: String?
        public var samples: Int
        public var audioPeaks: Int
        public var ballTracks: Int
    }
    public struct SwingEval: Codable {
        public var index: Int
        public var analysisIdentical: Bool
        public var analysisDiffAt: String?
        /// Whether the swing could be analysed at all, and why not ("no-orientation", …).
        public var ok: Bool
        public var reason: String?
        /// Keyframes with no pose (Vision found nobody), out of KEYFRAMES_PER_SWING.
        public var poselessKeyframes: Int
        public var native: [String: String]      // checkpoint → PASS / FAIL / —
        public var js: [String: String]
        /// Checkpoints where both sides gave the same PASS or FAIL.
        public var gradedMatches: Int
        /// Checkpoints that neither side could assess ("—" on both): agreement, but about nothing.
        public var bothUnassessed: Int
        public var checkpointMatches: Int { gradedMatches + bothUnassessed }
    }
    public var clip: String
    public var durationSec: Double
    public var native: Side
    public var js: Side
    /// Swings, capHit, every motion sample, every audio peak and every ball track compared in full.
    public var segmentationIdentical: Bool
    public var segmentationDiffAt: String?
    public var swings: [SwingEval]
    public var roundNative: [String: String]
    public var roundJS: [String: String]
    public var roundIdentical: Bool
    public var focusNative: String?
    public var focusJS: String?
    public var focusIdentical: Bool
    public var checkpointMatches: Int { swings.reduce(0) { $0 + $1.checkpointMatches } }
    public var gradedMatches: Int { swings.reduce(0) { $0 + $1.gradedMatches } }
    public var bothUnassessed: Int { swings.reduce(0) { $0 + $1.bothUnassessed } }
    public var checkpointTotal: Int { swings.count * 6 }
    /// Marks are computed on the native swing windows; they only mean "the same" when segmentation is.
    public var marksComparable: Bool { segmentationIdentical }
    /// Everything identical: the gate.
    public var identical: Bool {
        segmentationIdentical && roundIdentical && focusIdentical
            && swings.allSatisfy { $0.analysisIdentical && $0.checkpointMatches == 6 }
    }
}

public enum ParityRunner {

    static func label(_ m: [String: Any]?) -> String {
        guard let m, let assessed = m["assessed"] as? Bool, let pass = m["pass"] as? Bool else { return "?" }
        return assessed ? (pass ? "PASS" : "FAIL") : "—"
    }

    static func labels(_ marks: Any?) -> [String: String] {
        let d = marks as? [String: Any] ?? [:]
        return Dictionary(uniqueKeysWithValues: Tuning.checkpoints.map { ($0, label(d[$0] as? [String: Any])) })
    }

    static func encode<T: Encodable>(_ v: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(v), options: [.fragmentsAllowed])
    }
    /// Result types with internal numbers encode only through the package-level parity encoder.
    static func encode<T: ParityEncodable>(_ v: T) throws -> Any { try ParityJSON.object(v) }

    /// First path where two JSON trees differ (numbers to a 1e-9 relative tolerance), or nil.
    static func firstDiff(_ a: Any?, _ b: Any?, _ path: String = "$") -> String? {
        switch (a, b) {
        case (nil, nil), (is NSNull, is NSNull), (nil, is NSNull), (is NSNull, nil): return nil
        case let (x as [String: Any], y as [String: Any]):
            if Set(x.keys) != Set(y.keys) { return "\(path) (keys)" }
            for k in x.keys.sorted() { if let d = firstDiff(x[k], y[k], "\(path).\(k)") { return d } }
            return nil
        case let (x as [Any], y as [Any]):
            if x.count != y.count { return "\(path) (count \(x.count) vs \(y.count))" }
            for i in x.indices { if let d = firstDiff(x[i], y[i], "\(path)[\(i)]") { return d } }
            return nil
        case let (x as NSNumber, y as NSNumber):
            let xb = CFGetTypeID(x) == CFBooleanGetTypeID(), yb = CFGetTypeID(y) == CFBooleanGetTypeID()
            if xb || yb { return xb == yb && x.boolValue == y.boolValue ? nil : path }
            let dx = x.doubleValue, dy = y.doubleValue
            return dx == dy || abs(dx - dy) <= 1e-9 * max(1, abs(dx), abs(dy)) ? nil : path
        case let (x as String, y as String): return x == y ? nil : path
        default: return path
        }
    }

    public struct FeedError: Error, CustomStringConvertible { public let description: String }

    public static func run(_ url: URL, ageBand: String = "11-13",
                           progress: ((String) -> Void)? = nil) async throws -> ClipParity {
        let js = try JSReference()
        let library = try TipLibrary.bundled()
        js.ctx.evaluateScript("""
            window.__seg = { samples: [], ballFrames: [], prevM: null, prevB: null };
            // segment.js sampleMotion()'s push(), verbatim in behaviour: a sample per fresh frame
            window.__push = function (t, m, b) {
              const S = window.__seg;
              const fresh = t > (S.samples.length ? S.samples[S.samples.length - 1].t : -1);
              if (S.prevM && fresh) S.samples.push({ t, e: DugoutSegment.diffEnergy(m, S.prevM) });
              if (S.prevB && fresh) S.ballFrames.push({ t, blobs: DugoutSegment.ballBlobs(b, S.prevB) });
              S.prevM = m; S.prevB = b;
            };
        """)

        // ---- one decode, both segmenters ----
        // A JS exception inside the feed must fail the run, not vanish (it would otherwise surface,
        // if at all, only as a changed number much later).
        var feedError: String?
        func check(_ stage: String) { if feedError == nil, let e = js.jsError { feedError = "\(stage): \(e)" } }
        progress?("decoding + segmenting (Swift and JS on the same frames)")
        let seg = try await Segmenter.segment(url, observer: { t, m, b in
            js.setFloat32("__m", m.map(Float.init))
            js.setBytes("__b", b)
            js.ctx.evaluateScript("__push(\(t), __m, __b)")
            check("frame at \(t)")
        }, audioObserver: { samples, rate in
            js.setFloat32("__pcm", samples)
            js.ctx.evaluateScript("window.__audio = { samples: __pcm, rate: \(rate) };")
            check("audio")
        })
        if let feedError { throw FeedError(description: "JS threw while being fed frames — \(feedError)") }
        let jsSeg = try js.json("""
            DugoutSegment.audioPeaks(new Blob([])).then((peaks) => {
              const samples = __seg.samples;
              samples.ballFrames = __seg.ballFrames;              // as sampleMotion() returns them
              const r = __segTailRun(samples, peaks, \(seg.durationSec));   // segment()'s own lines
              return { swings: r.swings, capHit: r.capHit, samples, peaks, tracks: r.ballTracks };
            })
        """) as? [String: Any] ?? [:]

        let nativeSwingsJSON = try encode(seg.swings)
        let jsSwings = jsSeg["swings"] as? [Any] ?? []
        let jsCapHit = jsSeg["capHit"] as? String
        let nativeSamples = try encode(seg.samples), nativeTracks = try encode(seg.tracks)
        let segDiff = firstDiff(nativeSwingsJSON, jsSwings, "$.swings")
            ?? (seg.capHit == jsCapHit ? nil : "$.capHit")
            ?? firstDiff(nativeSamples, jsSeg["samples"], "$.samples")
            ?? firstDiff(seg.peaks, jsSeg["peaks"], "$.peaks")
            ?? firstDiff(nativeTracks, jsSeg["tracks"], "$.tracks")
        func side(_ arr: Any?) -> [ClipParity.Swing] {
            ((arr as? [[String: Any]]) ?? []).map {
                ClipParity.Swing(start: $0["start"] as? Double ?? .nan, end: $0["end"] as? Double ?? .nan,
                                 contactT: $0["contactT"] as? Double ?? .nan, audioConfirmed: $0["audioConfirmed"] as? Bool ?? false)
            }
        }

        // ---- evaluation: same Vision poses into both evaluators ----
        var evals: [ClipParity.SwingEval] = []
        var nativeAnalyses: [IdentifiedAnalysis] = []
        var jsAnalyses: [Any] = []
        try js.set("__phi", json: try encode(Philosophy.default))
        for (i, span) in seg.swings.enumerated() {
            progress?("swing \(i + 1)/\(seg.swings.count): Vision keyframe poses → both evaluators")
            let frames = try await KeyframePoser.poses(url, info: seg.info,
                                                       times: KeyframePoser.times(for: span, duration: seg.durationSec))
            let native = Evaluator.analyzeSwing(frames: frames, contactT: span.contactT, library: library)
            try js.set("__poses", json: try frames.map { f -> Any in try f.pose.map { try encode($0) } ?? NSNull() })
            try js.set("__frames", json: frames.indices.map { ["t": frames[$0].t, "blob": $0] as [String: Any] })
            let jsA = try js.json("""
                DugoutEvaluate.analyzeSwing(__frames, \(span.contactT)).then((r) => {
                  Object.values(r.faults || {}).forEach((f) => { delete f.detail; }); r.swingId = 'swing-\(i)'; return r; })
            """)
            jsAnalyses.append(jsA)
            nativeAnalyses.append(IdentifiedAnalysis(swingId: "swing-\(i)", analysis: native))
            let aDiff = firstDiff(try encode(native), (jsA as? [String: Any])?.filter { $0.key != "swingId" })

            let nativeMarks = Evaluator.marksForSwing(native, ageBand: ageBand, philosophy: .default, library: library)
            try js.set("__one", json: [jsA])
            let jsMarks = try js.json("DugoutEvaluate.rollup(__one, { ageBand: '\(ageBand)' }, __phi)")
            let n = labels(try encode(nativeMarks)), j = labels(jsMarks)
            let same = Tuning.checkpoints.filter { n[$0] == j[$0] }
            evals.append(ClipParity.SwingEval(
                index: i, analysisIdentical: aDiff == nil, analysisDiffAt: aDiff,
                ok: native.ok, reason: native.reason, poselessKeyframes: frames.filter { $0.pose == nil }.count,
                native: n, js: j,
                gradedMatches: same.filter { n[$0] != "—" }.count,
                bothUnassessed: same.filter { n[$0] == "—" }.count))
        }
        let nativeRound = Evaluator.rollup(nativeAnalyses, ageBand: ageBand, philosophy: .default, library: library)
        let nativeFocus = Evaluator.priorityFocus(nativeRound, philosophy: .default)
        try js.set("__all", json: jsAnalyses)
        let jsRoundAndFocus = try js.json("""
            (() => { const r = DugoutEvaluate.rollup(__all, { ageBand: '\(ageBand)' }, __phi);
                     return { round: r, focus: DugoutEvaluate.priorityFocus(r, __phi) }; })()
        """) as? [String: Any] ?? [:]
        let jsRound = jsRoundAndFocus["round"]
        let jsFocus = jsRoundAndFocus["focus"] as? String
        let roundDiff = firstDiff(try encode(nativeRound), jsRound)

        return ClipParity(
            clip: url.lastPathComponent, durationSec: seg.durationSec,
            native: .init(swings: side(nativeSwingsJSON), capHit: seg.capHit, samples: seg.sampleCount,
                          audioPeaks: seg.audioPeakCount, ballTracks: seg.ballTrackCount),
            js: .init(swings: side(jsSwings), capHit: jsCapHit, samples: (jsSeg["samples"] as? [Any])?.count ?? -1,
                      audioPeaks: (jsSeg["peaks"] as? [Any])?.count ?? -1, ballTracks: (jsSeg["tracks"] as? [Any])?.count ?? -1),
            segmentationIdentical: segDiff == nil, segmentationDiffAt: segDiff,
            swings: evals, roundNative: labels(try encode(nativeRound)), roundJS: labels(jsRound),
            roundIdentical: roundDiff == nil,
            focusNative: nativeFocus, focusJS: jsFocus, focusIdentical: nativeFocus == jsFocus)
    }
}
