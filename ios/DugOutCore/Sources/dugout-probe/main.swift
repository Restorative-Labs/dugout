// dugout-probe — run the native pipeline on one clip from the terminal.
//
//   dugout-probe timeline <clip.mov> [--timestamps]
//       P1.1: codec, resolution, orientation, nominal fps, frame count, and the real frame
//       spacing. --timestamps also prints every frame's presentation time.
//
//   dugout-probe pose <clip.mov> --csv <out.csv> [--contacts 4.27,31.58] [--window 0.5]
//                    [--at 19.9,20.2]
//       P1.2: Vision body pose on every frame. Writes per-frame joints to --csv and prints
//       median / 10th-percentile / mean confidence for wrists and elbows, overall and in a
//       window around each contact. --at prints wrist/elbow confidence at the frame nearest
//       each time (a confidence, never a position).
//
//   dugout-probe swings <clip.mov> [--age-band 11-13]
//       P1.3+P1.4: the whole native pipeline — swings found, and for each swing the six
//       checkpoint marks (PASS / FAIL / — for not measured), plus the round's marks and focus.
//
//   dugout-probe parity <clip.mov> [more clips…] [--json <out.json>]
//       The gate: Swift vs the app's own JS (in JavaScriptCore) on the same decoded frames and
//       the same Vision poses. Prints a table; never prints an internal score.
//
// The CSV holds pose keypoints of a real child (biometric, CANON R-13/R-30). It is refused
// anywhere inside a git working tree or a cloud-synced folder. Nothing printed here is ever a
// keypoint position.
import DugOutCore
import Foundation
import ProbeOutput
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func numbers(_ s: String?) -> [Double] {
    (s ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
}

func f(_ x: Double?, _ digits: Int = 3) -> String {
    x.map { String(format: "%.\(digits)f", $0) } ?? "—"
}

/// Why `url` is not an acceptable place for the keypoint CSV, or nil if it is.
/// Symlinks are resolved and the check walks real directories, so a case-variant path or a link
/// into a repo cannot slip past a string comparison.
func forbiddenLocation(for url: URL) -> String? {
    let fm = FileManager.default
    var dir = url.deletingLastPathComponent().standardizedFileURL
    while !fm.fileExists(atPath: dir.path), dir.path != "/" { dir = dir.deletingLastPathComponent() }
    dir = dir.resolvingSymlinksInPath()
    let home = fm.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path.lowercased()
    for synced in ["/library/cloudstorage/", "/library/mobile documents/"] {
        if (dir.path.lowercased() + "/").hasPrefix(home + synced) { return "it is a cloud-synced folder" }
    }
    var walk = dir
    while true {
        if fm.fileExists(atPath: walk.appendingPathComponent(".git").path) {
            return "it is inside the git working tree at \(walk.path)"
        }
        if walk.path == "/" { return nil }
        walk = walk.deletingLastPathComponent()
    }
}

func describe(_ o: CGImagePropertyOrientation) -> String {
    switch o {
    case .up: return "up (landscape as stored)"
    case .right: return "right (portrait: stored sideways, turn 90° clockwise)"
    case .left: return "left (portrait, upside-down phone)"
    case .down: return "down (landscape, turned 180°)"
    default: return "\(o.rawValue)"
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, ["timeline", "pose", "swings", "parity"].contains(args[0]) else {
    fail("usage: dugout-probe timeline <clip> [--timestamps]\n       dugout-probe pose <clip> --csv <out.csv> [--contacts a,b] [--window 0.5] [--at t1,t2]\n       dugout-probe swings <clip> [--age-band 11-13]\n       dugout-probe parity <clip> [clip…] [--json out.json]")
}
let url = URL(fileURLWithPath: args[1])
guard FileManager.default.fileExists(atPath: url.path) else { fail("No such file: \(url.path)") }

func header(_ info: VideoTrackInfo) {
    print("clip         \(url.lastPathComponent)")
    print("codec        \(info.codec)")
    print("encoded      \(info.width)×\(info.height)")
    print("orientation  \(describe(info.orientation))")
    print("nominal fps  \(f(info.nominalFPS, 3))")
    print("duration     \(f(info.duration, 3)) s")
}

switch args[0] {
case "timeline":
    let tl = try await ClipTimeline.read(url)
    header(tl.info)
    print("frames       \(tl.timestamps.count) camera frames   (edit filler skipped: \(tl.editFillerFrames) · imageless samples: \(tl.imagelessSamples))")
    for e in tl.info.emptyEdits {
        print("edit list    empty edit \(f(e.lowerBound, 3))–\(f(e.upperBound, 3)) s (timeline structure, not a dropped frame)")
    }
    print("first / last \(f(tl.timestamps.first, 6)) s / \(f(tl.timestamps.last, 6)) s")
    print("monotonic    \(tl.isMonotonic ? "yes" : "NO")")
    let expected = tl.info.nominalFPS > 0 ? 1 / tl.info.nominalFPS : nil
    print("delta        min \(f(tl.minDelta.map { $0 * 1000 }, 3)) ms · median \(f(tl.medianDelta.map { $0 * 1000 }, 3)) ms · max \(f(tl.maxDelta.map { $0 * 1000 }, 3)) ms   (nominal \(f(expected.map { $0 * 1000 }, 3)) ms)")
    let odd = tl.irregularDeltas()
    print("irregular    \(odd.count) gap(s) off nominal by >25%")
    for o in odd.prefix(20) {
        print("             frame \(o.index) at \(f(tl.timestamps[o.index], 6)) s: gap \(f(o.delta * 1000, 3)) ms")
    }
    if odd.count > 20 { print("             … \(odd.count - 20) more") }
    if args.contains("--timestamps") {
        print("\nframe,t")
        for (i, t) in tl.timestamps.enumerated() { print("\(i),\(String(format: "%.6f", t))") }
    }

case "pose":
    guard let csvPath = option("--csv", in: args) else { fail("pose needs --csv <out.csv>") }
    let csvURL = URL(fileURLWithPath: csvPath)
    if let why = forbiddenLocation(for: csvURL) {
        fail("Refusing to write pose keypoints to \(csvURL.path): \(why). They are biometric data of a minor — keep them local and outside any repo.")
    }
    let contacts = numbers(option("--contacts", in: args))
    let half = (Double(option("--window", in: args) ?? "0.5") ?? 0.5) / 2
    let at = numbers(option("--at", in: args))

    let started = Date()
    var lastShown = -10.0
    let run = try await PoseRun.run(url) { t in
        if t - lastShown >= 5 {
            lastShown = t
            FileHandle.standardError.write("  … \(Int(t)) s\n".data(using: .utf8)!)
        }
    }
    try PoseCSV.write(run.frames, to: csvURL)
    let secs = Date().timeIntervalSince(started)

    header(run.info)
    let n = run.frames.count
    let withPerson = run.frames.filter { $0.people > 0 }.count
    let crowded = run.frames.filter { $0.people > 1 }.count
    print("frames       \(n) camera frames · person found in \(withPerson) (\(f(100 * Double(withPerson) / Double(max(n, 1)), 1))%) · >1 person in \(crowded)")
    if run.skipped.editFiller + run.skipped.imageless > 0 {
        print("skipped      \(run.skipped.editFiller) edit-filler frame(s), \(run.skipped.imageless) imageless sample(s) — not footage, never sent to Vision")
    }
    print("model        VNDetectHumanBodyPoseRequest revision \(run.modelRevision)")
    print("wall time    \(f(secs, 1)) s (\(f(1000 * secs / Double(max(n, 1)), 1)) ms/frame incl. decode)")
    print("csv          \(csvURL.path)")

    let rows: [(String, [TrackedJoint])] = [
        ("L wrist", [.leftWrist]), ("R wrist", [.rightWrist]), ("wrists", [.leftWrist, .rightWrist]),
        ("L elbow", [.leftElbow]), ("R elbow", [.rightElbow]), ("elbows", [.leftElbow, .rightElbow]),
    ]
    var windows: [(String, ClosedRange<Double>?)] = [("overall", nil)]
    for c in contacts { windows.append(("@\(f(c, 2))s", (c - half)...(c + half))) }

    func cell(_ s: ConfidenceSummary?) -> String {
        guard let s else { return "—" }
        return "\(f(s.median)) / \(f(s.p10)) / \(f(s.mean))"
    }
    print("\nconfidence: median / p10 / mean  (misses count as 0; contact windows ±\(f(half, 2)) s)")
    let colW = 23
    var line = "".padding(toLength: 9, withPad: " ", startingAt: 0)
    for (name, _) in windows { line += name.padding(toLength: colW, withPad: " ", startingAt: 0) }
    if contacts.count > 1 { line += "all contacts" }
    print(line)
    for (name, joints) in rows {
        var l = name.padding(toLength: 9, withPad: " ", startingAt: 0)
        for (_, w) in windows {
            l += cell(PoseSummary.summarize(run.frames, joints: joints, in: w))
                .padding(toLength: colW, withPad: " ", startingAt: 0)
        }
        if contacts.count > 1 {
            let pooled = run.frames.filter { fr in contacts.contains { abs(fr.t - $0) <= half } }
            l += cell(PoseSummary.summarize(pooled, joints: joints))
        }
        print(l)
    }
    if contacts.count > 0 {
        var counts = "frames   "
        for (_, w) in windows {
            counts += "\(PoseSummary.summarize(run.frames, joints: [.leftWrist], in: w)?.frames ?? 0)"
                .padding(toLength: colW, withPad: " ", startingAt: 0)
        }
        if contacts.count > 1 {
            counts += "\(run.frames.filter { fr in contacts.contains { abs(fr.t - $0) <= half } }.count)"
        }
        print(counts)
    }

    if !at.isEmpty {
        print("\nnearest frame to each --at time: wrist L / R · elbow L / R")
        for t in at {
            guard let fr = run.frames.min(by: { abs($0.t - t) < abs($1.t - t) }) else { continue }
            print("  t=\(f(t, 2))  (frame \(f(fr.t, 3)) s)  wrist \(f(fr.confidence(.leftWrist), 2)) / \(f(fr.confidence(.rightWrist), 2)) · elbow \(f(fr.confidence(.leftElbow), 2)) / \(f(fr.confidence(.rightElbow), 2))")
        }
    }

case "swings":
    let band = option("--age-band", in: args) ?? "11-13"
    let r = try await RoundAnalyzer.analyze(url, ageBand: band)
    header(r.segmentation.info)
    let seg = r.segmentation
    print("swings       \(r.swings.count)\(seg.capHit.map { "  (cap hit: \($0))" } ?? "")  · motion samples \(seg.sampleCount) · audio peaks \(seg.audioPeakCount) · ball tracks \(seg.ballSaturated ? "saturated → ignored" : String(seg.ballTrackCount))")
    func mark(_ m: CheckpointMark?) -> String { guard let m else { return "?" }; return m.assessed ? (m.pass ? "PASS" : "FAIL") : "—" }
    print("\n#  window (s)        contact  audio  " + Tuning.checkpoints.map { Tuning.checkpointLabel[$0]!.padding(toLength: 10, withPad: " ", startingAt: 0) }.joined())
    for s in r.swings {
        let w = "\(f(s.span.start, 2))–\(f(s.span.end, 2))".padding(toLength: 18, withPad: " ", startingAt: 0)
        var line = "\(s.index + 1)  \(w)\(f(s.span.contactT, 2).padding(toLength: 9, withPad: " ", startingAt: 0))\((s.span.audioConfirmed ? "yes" : "no").padding(toLength: 7, withPad: " ", startingAt: 0))"
        line += s.analysis.ok ? Tuning.checkpoints.map { mark(s.marks[$0]).padding(toLength: 10, withPad: " ", startingAt: 0) }.joined()
                              : "not analysed (\(s.analysis.reason ?? "?"))"
        print(line)
    }
    print("round        " + Tuning.checkpoints.map { "\(Tuning.checkpointLabel[$0]!) \(mark(r.roundMarks[$0]))" }.joined(separator: " · "))
    let graded = r.roundMarks.values.contains { $0.assessed }
    print("focus        \(r.focus.map { Tuning.checkpointLabel[$0]! } ?? (graded ? "none — every graded checkpoint passed" : "NOTHING COULD BE GRADED"))")

case "parity":
    let clips = args.dropFirst().filter { !$0.hasPrefix("--") && $0 != option("--json", in: args) }.map { URL(fileURLWithPath: $0) }
    var reports: [ClipParity] = []
    for clip in clips {
        FileHandle.standardError.write("\(clip.lastPathComponent)…\n".data(using: .utf8)!)
        reports.append(try await ParityRunner.run(clip) { FileHandle.standardError.write("  \($0)\n".data(using: .utf8)!) })
    }
    // Decision-logic parity: both sides read the SAME native frames and Vision poses. It proves the
    // port, not that native finds what the web app finds on the phone (CANON R-44).
    func pad(_ x: String, _ n: Int) -> String { x.padding(toLength: n, withPad: " ", startingAt: 0) }
    print(pad("clip", 19) + pad("JS logic", 10) + pad("native", 8) + pad("segmentation", 30)
          + pad("graded agree", 14) + pad("— on both", 11) + pad("round", 11) + "focus")
    for r in reports {
        let seg = r.segmentationIdentical ? "identical" : "DIFFERS at \(r.segmentationDiffAt ?? "?")"
        let graded = r.checkpointTotal - r.bothUnassessed
        print(pad(r.clip, 19) + pad("\(r.js.swings.count)", 10) + pad("\(r.native.swings.count)", 8) + pad(seg, 30)
              + (r.marksComparable
                 ? pad("\(r.gradedMatches)/\(graded)", 14) + pad("\(r.bothUnassessed)", 11)
                   + pad(r.roundIdentical ? "identical" : "DIFFERS", 11) + (r.focusIdentical ? "identical" : "DIFFERS")
                 : "n/a (segmentation differs)"))
        for s in r.swings {
            var notes: [String] = []
            if !s.analysisIdentical { notes.append("analysis differs at \(s.analysisDiffAt ?? "?")") }
            if !s.ok { notes.append("not analysed (\(s.reason ?? "?"))") }
            if s.poselessKeyframes > 0 { notes.append("\(s.poselessKeyframes)/\(Tuning.keyframesPerSwing) keyframes with nobody found") }
            if !notes.isEmpty { print("   swing \(s.index + 1): " + notes.joined(separator: " · ")) }
        }
    }
    let total = reports.reduce(0) { $0 + $1.checkpointTotal }, both = reports.reduce(0) { $0 + $1.bothUnassessed }
    print("total        \(reports.reduce(0) { $0 + $1.gradedMatches })/\(total - both) graded marks agree · \(both) not assessed on either side · "
          + (reports.allSatisfy(\.identical) ? "ALL IDENTICAL" : "NOT IDENTICAL"))
    if let out = option("--json", in: args) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(reports).write(to: URL(fileURLWithPath: out))
        print("json         \(out)")
    }

default:
    fail("unknown command \(args[0])")
}
