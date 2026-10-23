import XCTest
@testable import DugOutCore
@testable import ProbeOutput

/// P1.4 parity: js/evaluate.js vs the Swift port on IDENTICAL pose tracks. The JS side runs its
/// real analyzeSwing (buildTrack's sampling, orient, all fifteen detectors, the try/catch), with
/// only the pose estimator stubbed to return the test's poses.
final class EvaluateParityTests: XCTestCase {
    var js: JSReference!
    var library: TipLibrary!

    override func setUpWithError() throws {
        js = try JSReference()
        library = try TipLibrary.bundled()
    }

    static let moveNetNames = [
        "nose", "left_eye", "right_eye", "left_ear", "right_ear", "left_shoulder", "right_shoulder",
        "left_elbow", "right_elbow", "left_wrist", "right_wrist", "left_hip", "right_hip",
        "left_knee", "right_knee", "left_ankle", "right_ankle",
    ]

    /// A batter-ish figure in 540×304 keyframe pixels that drifts, rotates and loses joints.
    static func randomSwing(_ rng: inout SeededRandom) -> [KeyframePose] {
        let base: [String: (Double, Double)] = [
            "nose": (270, 60), "left_eye": (266, 56), "right_eye": (274, 56), "left_ear": (262, 58), "right_ear": (278, 58),
            "left_shoulder": (255, 90), "right_shoulder": (285, 90), "left_elbow": (245, 120), "right_elbow": (295, 120),
            "left_wrist": (250, 140), "right_wrist": (290, 140), "left_hip": (260, 165), "right_hip": (280, 165),
            "left_knee": (255, 215), "right_knee": (285, 215), "left_ankle": (250, 265), "right_ankle": (290, 265),
        ]
        // t = i/10 exactly (u = t): at(track, 0.05) is an exact tie between u = 0 and u = 0.1, so the
        // first-on-tie rule decides which frame stride.bucket / backsideCollapse read
        let tieTrack = rng.chance(0.12)
        let n = tieTrack ? 11 : (rng.chance(0.85) ? 24 : rng.int(0, 34))
        let frozenHips = rng.chance(0.1)                  // exercises maxDeriv with zero rate (null u)
        let dropJointP = tieTrack ? 0 : [0.0, 0.1, 0.4, 0.9][rng.int(0, 3)]
        let walk = rng.range(0, 60), rot = rng.range(-30, 30)
        // vertical travel, so the y-reading detectors (bucket's lateral, backsideCollapse's drop,
        // headMove's dy) see values inside their ramps, not a constant 0
        let hipDrop = rng.range(-8, 45), noseDy = rng.range(-30, 30), ankleDy = rng.range(-70, 70)
        let start = rng.range(0, 30), span = rng.range(0.5, 6)
        return (0..<n).map { i in
            let t = tieTrack ? Double(i) / 10 : start + span * (n > 1 ? Double(i) / Double(n - 1) : 0)
            if !tieTrack && rng.chance(0.06) { return KeyframePose(t: t, pose: nil) }   // MoveNet found nobody
            let f = n > 1 ? Double(i) / Double(n - 1) : 0
            let kps = moveNetNames.map { name -> Keypoint in
                var (x, y) = base[name]!
                let jitter = rng.range(-6, 6)
                if frozenHips && name.contains("hip") {
                    // perfectly still hips: hipSep never changes, so maxDeriv finds no peak (u = null)
                    return Keypoint(name: name, x: x, y: y, score: 0.9)
                }
                x += walk * f + jitter
                if name == "nose" { y += noseDy * f + rng.range(-3, 3) }
                if name.contains("hip") { y += hipDrop * f }
                if name.contains("ankle") { y += ankleDy * f * (name.hasPrefix("left") ? 1 : 0.3) }
                if name.contains("hip"), !frozenHips { x += (name.hasPrefix("left") ? -1 : 1) * rot * sin(f * .pi) }
                if name.contains("shoulder") { x += (name.hasPrefix("left") ? -1 : 1) * rot * sin(min(1, f * 1.2) * .pi) }
                if name.contains("wrist") || name.contains("elbow") { x += rng.range(-40, 40) * f; y += rng.range(-30, 30) * f }
                if name.contains("ankle"), name.hasPrefix(rng.chance(0.5) ? "left" : "right") { x += rng.range(-80, 80) * f }
                let score = rng.chance(dropJointP) ? rng.range(0, 0.35) : rng.range(0.25, 1)
                return Keypoint(name: name, x: x, y: y, score: score)
            }
            return KeyframePose(t: t, pose: Pose(keypoints: kps))
        }
    }

    private func jsAnalyze(_ frames: [KeyframePose], contactT: Double?) throws -> Any {
        try js.set("__poses", json: try frames.map { f -> Any in try f.pose.map { try jsonObject($0) } ?? NSNull() })
        try js.set("__frames", json: frames.indices.map { ["t": frames[$0].t, "blob": $0] as [String: Any] })
        let ct = contactT.map { String($0) } ?? "null"
        // `detail` strings are display text with toFixed(); the port carries the numbers, not the text
        return try js.json("""
            DugoutEvaluate.analyzeSwing(__frames, \(ct)).then((r) => {
              Object.values(r.faults || {}).forEach((f) => { delete f.detail; }); return r; })
        """)
    }

    func testAnalyzeSwingMatchesOnRandomTracks() throws {
        var rng = SeededRandom(seed: 11)
        var analysed = 0, manyFaults = 0, zeroRateHips = 0
        var inRamp: [String: Int] = [:]                  // detector → trials with conf strictly inside its range
        for trial in 0..<400 {
            let frames = Self.randomSwing(&rng)
            let contactT: Double? = rng.chance(0.8) ? (frames.first?.t ?? 0) + rng.range(-1, 5) : nil
            let expected = try jsAnalyze(frames, contactT: contactT)
            let a = Evaluator.analyzeSwing(frames: frames, contactT: contactT, library: library)
            if let d = jsonDifference(try jsonObject(a), expected) { XCTFail("trial \(trial) (seed 11): \(d)"); return }
            if a.ok { analysed += 1 }
            if a.faults.count >= 10 { manyFaults += 1 }
            for (id, f) in a.faults where f.conf > 0 && f.conf < 1 && f.conf != 0.55 { inRamp[id, default: 0] += 1 }
            if let track = Evaluator.buildTrack(frames), track.count > 2 {
                let sig = Evaluator.series(track) { $0.hipSep }
                if sig.count > 2, Evaluator.maxDeriv(sig).u == nil { zeroRateHips += 1 }
            }
        }
        // the hard paths have to have been exercised, or parity proves nothing about them
        XCTAssertGreaterThan(analysed, 200)
        XCTAssertGreaterThan(manyFaults, 100)
        XCTAssertGreaterThan(zeroRateHips, 5, "maxDeriv's null-u path (JS: null coerces to 0) never ran")
        // every detector must have been read inside its ramp, not only pinned at 0 or 1 — a detector
        // only ever seen saturated would hide a wrong ramp end (the review's E2/E3/E6 mutations)
        XCTAssertEqual(inRamp.count, 18, "only these faults were read inside their range: \(inRamp.keys.sorted())")
        for (id, n) in inRamp { XCTAssertGreaterThanOrEqual(n, 10, "\(id) read inside its range in only \(n) trials") }
    }

    func testRollupAndPriorityFocusMatch() throws {
        var rng = SeededRandom(seed: 12)
        var focused = 0, ties = 0
        let checkpoints = Tuning.checkpoints
        for trial in 0..<200 {
            var analyses: [IdentifiedAnalysis] = []
            var jsResults: [Any] = []
            for k in 0..<rng.int(0, 8) {
                let frames = Self.randomSwing(&rng)
                let a = Evaluator.analyzeSwing(frames: frames, contactT: frames.first.map { $0.t + 1 }, library: library)
                analyses.append(IdentifiedAnalysis(swingId: "s\(k)", analysis: a))
                var obj = try XCTUnwrap(try jsonObject(a) as? [String: Any]); obj["swingId"] = "s\(k)"
                jsResults.append(obj)
            }
            let band = ["7-10", "11-13", "14-18"][rng.int(0, 2)]
            let tipIds = library.tips.map(\.id)
            let philosophy = Philosophy(
                tipSelections: rng.chance(0.5) ? [:] : Dictionary(uniqueKeysWithValues: checkpoints.compactMap { cp in
                    rng.chance(0.5) ? (cp, library.tips.filter { $0.checkpoint == cp && rng.chance(0.6) }.map(\.id)) : nil }),
                priorities: rng.chance(0.5) ? [] : checkpoints.shuffled(using: &rng),
                redLineTipIds: tipIds.filter { _ in rng.chance(0.1) })
            try js.set("__results", json: jsResults)
            try js.set("__phi", json: try jsonObject(philosophy))
            let expected = try XCTUnwrap(try js.json("""
                (() => { const pc = DugoutEvaluate.rollup(__results, { ageBand: '\(band)' }, __phi);
                         return { perCheckpoint: pc, focus: DugoutEvaluate.priorityFocus(pc, __phi) }; })()
            """) as? [String: Any])
            let marks = Evaluator.rollup(analyses, ageBand: band, philosophy: philosophy, library: library)
            let got: [String: Any] = [
                "perCheckpoint": try jsonObject(marks),
                "focus": Evaluator.priorityFocus(marks, philosophy: philosophy) as Any? ?? NSNull(),
            ]
            if let d = jsonDifference(got, expected) { XCTFail("trial \(trial) (seed 12): \(d)"); return }
            let fails = Tuning.checkpoints.filter { marks[$0]!.assessed && !marks[$0]!.pass }
            if !fails.isEmpty { focused += 1 }
            let scores = fails.compactMap { marks[$0]!.internalScore }
            if scores.count > 1, scores.indices.contains(where: { i in scores.indices.contains { j in j != i && abs(scores[i] - scores[j]) <= 0.02 } }) {
                ties += 1
            }
        }
        XCTAssertGreaterThan(focused, 40, "too few rounds failed a checkpoint")
        XCTAssertGreaterThan(ties, 5, "the 0.02 tie-break (sort-algorithm dependent) was never exercised")
    }

    /// priorityFocus's comparator is not transitive (|d| ≤ 0.02 falls back to order), so on chained
    /// near-ties the answer depends on the sort algorithm itself. Build exactly those chains.
    func testPriorityFocusOnNonTransitiveNearTies() throws {
        var rng = SeededRandom(seed: 13)
        var disagreementsAlgorithmCouldCause = 0
        for trial in 0..<3000 {
            let centre = rng.range(0.2, 0.58)
            var marks: [String: CheckpointMark] = [:]
            for cp in Tuning.checkpoints {
                let assessed = rng.chance(0.9)
                let score = centre + rng.range(-0.035, 0.035)
                marks[cp] = CheckpointMark(pass: !assessed ? true : score >= 0.6, assessed: assessed,
                                           internalScore: assessed ? score : nil, faultIds: [], evidenceSwingIds: [])
            }
            let phi = Philosophy(tipSelections: [:],
                                 priorities: rng.chance(0.3) ? [] : Tuning.checkpoints.shuffled(using: &rng),
                                 redLineTipIds: [])
            try js.set("__pc", json: try jsonObject(marks))
            try js.set("__phi", json: try jsonObject(phi))
            let expected = try js.json("DugoutEvaluate.priorityFocus(__pc, __phi)")
            let got = Evaluator.priorityFocus(marks, philosophy: phi)
            let expectedName = expected as? String
            XCTAssertEqual(got, expectedName, "trial \(trial) (seed 13)")
            if got != expectedName { return }
            // would a naive "lowest score, then order" pick differ? then this trial discriminates
            let fails = Tuning.checkpoints.filter { marks[$0]!.assessed && !marks[$0]!.pass }
            let naive = fails.min { marks[$0]!.internalScore! < marks[$1]!.internalScore! }
            if naive != expectedName { disagreementsAlgorithmCouldCause += 1 }
        }
        XCTAssertGreaterThan(disagreementsAlgorithmCouldCause, 100, "near-tie trials did not exercise the tie-break")
    }

    /// The sort port, compared call for call with JavaScriptCore's own Array.prototype.sort.
    func testSortMatchesJavaScriptCoreCallForCall() throws {
        var rng = SeededRandom(seed: 14)
        for trial in 0..<1000 {
            let values = (0..<rng.int(0, 20)).map { _ in Double(rng.int(0, 4)) + (rng.chance(0.5) ? 0 : 0.01) }
            try js.set("__vals", json: values.indices.map { ["i": $0, "v": values[$0]] as [String: Any] })
            let expected = try XCTUnwrap(try js.json("""
                (() => { const log = []; const a = __vals.slice();
                  a.sort((x, y) => { log.push([x.i, y.i]); const d = x.v - y.v; return Math.abs(d) > 0.02 ? d : 0; });
                  return { log, order: a.map((e) => e.i) }; })()
            """) as? [String: Any])
            var log: [[Int]] = []
            var order = Array(values.indices)
            Evaluator.jscSort(&order) { x, y in
                log.append([x, y]); let d = values[x] - values[y]; return abs(d) > 0.02 ? d : 0
            }
            if let d = jsonDifference(["log": log, "order": order], expected) { XCTFail("trial \(trial) (seed 14): \(d) values=\(values) swift=\(log) js=\(expected["log"]!)"); return }
        }
    }
}
