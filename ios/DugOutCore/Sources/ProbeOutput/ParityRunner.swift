import AVFoundation
import DugOutCore
import Foundation
import JavaScriptCore

/// End-to-end parity on a real clip — TEST TOOLING, never linked by the app.
///
/// One decode of the clip feeds BOTH implementations the same measurements:
///   * segmentation: every frame's upright motion/ball grids and the decoded audio go to the Swift
///     Segmenter and, identically, to the app's own segment.js functions running in JavaScriptCore
///     (diffEnergy, ballBlobs, linkBallTracks, audioPeaks, findSwings);
///   * evaluation: the same Vision keyframe poses go to the Swift Evaluator and to evaluate.js's
///     real analyzeSwing / rollup.
/// So any difference is a port bug, not a decoder, codec or pose-model difference — those are
/// what the browser-vs-native comparison measures, and they are reported separately.
///
/// Reports carry PASS/FAIL and counts only. Where two values differ, only the PATH of the
/// difference is reported — never an internal score (R-02).
public struct ClipParity: Codable {
    public struct Swing: Codable { public var start: Double; public var end: Double; public var contactT: Double; public var audioConfirmed: Bool }
    public struct Side: Codable {
        public var swings: [Swing]
        public var samples: Int
        public var audioPeaks: Int
        public var ballTracks: Int
    }
    public struct SwingEval: Codable {
        public var index: Int
        public var analysisIdentical: Bool
        public var analysisDiffAt: String?
        public var native: [String: String]      // checkpoint → PASS / FAIL / —
        public var js: [String: String]
        public var checkpointMatches: Int
    }
    public var clip: String
    public var durationSec: Double
    public var native: Side
    public var js: Side
    public var segmentationIdentical: Bool
    public var segmentationDiffAt: String?
    public var swings: [SwingEval]
    public var roundNative: [String: String]
    public var roundJS: [String: String]
    public var roundIdentical: Bool
    public var checkpointMatches: Int { swings.reduce(0) { $0 + $1.checkpointMatches } }
    public var checkpointTotal: Int { swings.count * 6 }
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
        progress?("decoding + segmenting (Swift and JS on the same frames)")
        let seg = try await Segmenter.segment(url, observer: { t, m, b in
            js.setFloat32("__m", m.map(Float.init))
            js.setBytes("__b", b)
            js.ctx.evaluateScript("__push(\(t), __m, __b)")
        }, audioObserver: { samples, rate in
            js.setFloat32("__pcm", samples)
            js.ctx.evaluateScript("window.__audio = { samples: __pcm, rate: \(rate) };")
        })
        let jsSeg = try js.json("""
            DugoutSegment.audioPeaks(new Blob([])).then((peaks) => {
              let tracks = DugoutSegment.linkBallTracks(__seg.ballFrames);
              if (tracks.length > DUGOUT_CONFIG.BALL_MAX_TRACKS) tracks = [];   // segment(): saturation guard
              let swings = DugoutSegment.findSwings(__seg.samples, peaks, tracks);
              const CFG = DUGOUT_CONFIG, durationSec = \(seg.durationSec);
              if (durationSec > CFG.CAP_SECONDS) {                              // segment(): caps
                swings = swings.filter((s) => s.start < CFG.CAP_SECONDS);
                swings.forEach((s) => { s.end = Math.min(s.end, CFG.CAP_SECONDS); });
              }
              if (swings.length > CFG.CAP_SWINGS) swings = swings.slice(0, CFG.CAP_SWINGS);
              return { swings, samples: __seg.samples.length, peaks: peaks.length, tracks: tracks.length };
            })
        """) as? [String: Any] ?? [:]

        let nativeSwingsJSON = try encode(seg.swings)
        let jsSwings = jsSeg["swings"] as? [Any] ?? []
        let segDiff = firstDiff(nativeSwingsJSON, jsSwings)
        func side(_ arr: Any?) -> [ClipParity.Swing] {
            ((arr as? [[String: Any]]) ?? []).map {
                ClipParity.Swing(start: $0["start"] as? Double ?? .nan, end: $0["end"] as? Double ?? .nan,
                                 contactT: $0["contactT"] as? Double ?? .nan, audioConfirmed: $0["audioConfirmed"] as? Bool ?? false)
            }
        }

        // ---- evaluation: same Vision poses into both evaluators ----
        let asset = AVURLAsset(url: url)
        var evals: [ClipParity.SwingEval] = []
        var nativeAnalyses: [IdentifiedAnalysis] = []
        var jsAnalyses: [Any] = []
        for (i, span) in seg.swings.enumerated() {
            progress?("swing \(i + 1)/\(seg.swings.count): Vision keyframe poses → both evaluators")
            let frames = try await KeyframePoser.poses(asset: asset, info: seg.info,
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
            try js.set("__phi", json: try encode(Philosophy.default))
            let jsMarks = try js.json("DugoutEvaluate.rollup(__one, { ageBand: '\(ageBand)' }, __phi)")
            let n = labels(try encode(nativeMarks)), j = labels(jsMarks)
            evals.append(ClipParity.SwingEval(index: i, analysisIdentical: aDiff == nil, analysisDiffAt: aDiff,
                                              native: n, js: j,
                                              checkpointMatches: Tuning.checkpoints.filter { n[$0] == j[$0] }.count))
        }
        let nativeRound = Evaluator.rollup(nativeAnalyses, ageBand: ageBand, philosophy: .default, library: library)
        try js.set("__all", json: jsAnalyses)
        let jsRound = try js.json("DugoutEvaluate.rollup(__all, { ageBand: '\(ageBand)' }, __phi)")
        let roundDiff = firstDiff(try encode(nativeRound), jsRound)

        return ClipParity(
            clip: url.lastPathComponent, durationSec: seg.durationSec,
            native: .init(swings: side(nativeSwingsJSON), samples: seg.sampleCount, audioPeaks: seg.audioPeakCount,
                          ballTracks: seg.ballTrackCount),
            js: .init(swings: side(jsSwings), samples: jsSeg["samples"] as? Int ?? -1,
                      audioPeaks: jsSeg["peaks"] as? Int ?? -1, ballTracks: jsSeg["tracks"] as? Int ?? -1),
            segmentationIdentical: segDiff == nil, segmentationDiffAt: segDiff,
            swings: evals, roundNative: labels(try encode(nativeRound)), roundJS: labels(jsRound),
            roundIdentical: roundDiff == nil)
    }
}
