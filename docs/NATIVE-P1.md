# DugOut — native rebuild, Phase 1: the pipeline

**Status:** active build brief. Phase 1 only. No UI in this phase.
**Ruled 2026-10-14:** DugOut is a native iOS app in Swift. Capture is native. The
website is marketing, information and login only. Full reasoning and the sizing:
`claude/native-rebuild-plan.md` in the Claude project.

---

## 0. Why the pipeline comes first

The screens are the certain part. The pipeline is where the risk and the
hard-won knowledge are, and it is also where this product fails — quietly,
while continuing to render six believable marks.

So Phase 1 builds the whole analysis path **headless, with no screens at all**,
and proves it against the existing JavaScript on the same footage before a
single view is written. If native cannot reproduce JS, that is learned in week
one instead of month four.

**The JavaScript implementation is not being replaced yet. It is the reference.**
`main` keeps working. Nothing in `js/` is deleted or edited in this phase.

---

## 1. What already exists, and what it is worth

| File | Lines | Fate |
|---|---|---|
| `js/segment.js` | 548 | **PORT.** Motion sampling, ball detection, audio transients, swing extraction, keyframes. |
| `js/evaluate.js` | 459 | **PORT.** Track building, geometry, the six checkpoints, rollup, priority focus. |
| `js/config.js` | 142 | **TRANSFER.** Empirical constants. Starting values, not answers. |
| `js/pose.js` | 112 | **DELETE.** Replaced by Vision. Read it first — see §4. |
| `js/shell.js`, `js/filmshell.js` | 931 | **DELETE.** Webview bridge. No native equivalent needed. |
| `ios/DugOut/LocalHTTPServer.swift` | — | **DELETE later.** Exists only to make `localhost` a secure context for `getUserMedia`. |
| `vendor/` | 5.7 MB | **DELETE.** TensorFlow.js + the MoveNet model. Vision ships with the OS. |
| `js/library.js` | 1,478 | Not this phase. Content, becomes a bundled resource. |

**The irreplaceable logic is ~1,150 lines.** Everything else is deleted, data,
or UI. This is a smaller job than it looks.

## 2. Read these before writing any code

In the repo:
- `CLAUDE.md` — conventions, the surface split, the session ritual
- `docs/CANON.md` — the ruling ledger. **R-13, R-14, R-15 bear directly on this work**
- `docs/SEGMENTATION-TDD.md` — how swing-finding is supposed to work
- `docs/POSE-PROBE.md` — why pose is two-pass today, and the measurements behind it
- `js/segment.js`, `js/evaluate.js`, `js/config.js`, `js/pose.js`

Read them. Do not skim and reimplement from the function names: the value in
those 1,150 lines is the thresholds and the edge cases, not the structure.

## 3. Where the code goes

**A Swift Package, not an app target.** `ios/DugOutKit/` as a local package,
plus a thin command-line executable target that takes a file path and prints
JSON.

Why: the pipeline must be runnable and testable from the terminal without
launching an app, against real clips, in a loop. A package gives you
`swift test` and a CLI. The app target depends on it in Phase 3.

```
ios/DugOutKit/
  Package.swift
  Sources/DugOutKit/        the library
  Sources/dugout-probe/     CLI: dugout-probe <clip.mov> [--json]
  Tests/DugOutKitTests/
```

Minimum deployment target: whatever `ios/DugOut.xcodeproj` already sets. Do not
raise it without saying so.

## 4. The finding that drives this phase

`js/pose.js` documents its own defect in the header comment. Quoting the repo:

- MoveNet SinglePose.Lightning takes a **192×192** input.
- The batter fills **~10% of frame width**, so the model sees him **~19 px wide**.
- **Wrists score ~0.3** — the comment's own word is *noise*.
- A two-pass crop-and-rerun hack roughly doubles wrist and elbow confidence.
- **"CT-05/CT-06 are *defined* on elbow-vs-wrist geometry."**
- First inference costs **~12.5 s** of shader compile, burned on a blank canvas
  at startup so it never lands on the user's first swing.

So two of the six checkpoints are computed from inputs the code calls noise, and
the product renders two confident PASS/FAIL marks anyway.

**R-15** (`CONTACT_ANCHOR: 0.62` not honoured; measured 0.500 / 0.761 / 0.572)
has been blamed on frame timing through a proxy codec. That is at most half of
it. The other half is keypoint quality.

Phase 1 settles both, by measurement rather than argument.

## 5. The sprints

One week each (≤1 week is ruled). Each has one outcome and one acceptance test.
**Do not start the next until the current one's acceptance passes.**

### P1.1 · The frame timeline is trustworthy

Build the package skeleton and the CLI. `AVAssetReader` over the clip. No pose,
no analysis.

Print per clip: codec, resolution, nominal fps, frame count, and **every frame's
real presentation timestamp**, plus the min/median/max inter-frame delta.

> **Acceptance:** `dugout-probe pitch_01.mov` prints a frame timeline whose
> timestamps are monotonic and whose deltas are consistent with the nominal
> frame rate. Any variable-frame-rate behaviour is reported, not smoothed over.

This is the smallest possible first step and it answers the biggest question:
whether the JS layer's timing was ever trustworthy. Everything downstream
depends on the answer.

### P1.2 · Pose is better than MoveNet, or it isn't

`VNDetectHumanBodyPose` over the frames from P1.1. Dump every joint with its
confidence, per frame, as JSON.

> **Acceptance:** report **mean and median wrist and elbow confidence** across
> `pitch_01–06.mov`, measured the same way `docs/POSE-PROBE.md` measured
> MoveNet's ~0.3. State plainly whether Vision beats it, matches it, or doesn't.
> **No single-pass/two-pass crop hack.** If Vision needs one too, that is a
> finding, and it goes in CANON before any workaround is written.

**This test can fail, and that is the point.** If Vision also scores ~0.3 on a
19-pixel subject, the architecture case weakens significantly and we learn it in
week two for the price of two sprints.

### P1.3 · The detector finds the same swings

Port `js/segment.js`: motion sampling, ball detection, audio transients, swing
extraction, keyframes. Constants from `js/config.js`, transferred verbatim as
**starting values**.

> **Acceptance:** on all six clips, native returns the same swing count as the
> current JS implementation, with swing boundaries within one frame. Where it
> differs, the difference is explained before anything is tuned.

**Do not tune a constant to make a test pass.** If a value needs changing, that
is a CANON amendment with a measurement behind it, not a code edit.

### P1.4 · The six checkpoints agree

Port `js/evaluate.js`: track building, geometry, the six checkpoints, rollup,
priority focus.

> **Acceptance:** per swing, per checkpoint, native PASS/FAIL matches JS. Any
> disagreement is reported with the frame and the geometry, not resolved by
> adjusting a threshold.

### P1.5 · R-14 and R-15 are settled

With real timestamps and real keypoints, re-run the measurements the two open
rulings are waiting on.

> **Acceptance:** `SPIKE_ENTER_MULT = 2.4` is confirmed or corrected on original
> H.264 across all five `pitch_0*.mov` clips (R-14 moves from PROVISIONAL to
> RULED, or the value changes). `CONTACT_ANCHOR` is measured and the real
> contact position reported (R-15 / DUG-54). Both go into CANON with the numbers.

---

## 6. Hard rules — these are not style preferences

- **Never logged, at any level, in any environment** (R-13): clip bytes or
  frames, pose keypoints, a child's name, internal checkpoint scores, auth
  tokens, Apple identity tokens. Logs reference the opaque `profileId` only.
  `DEBUG: true` is a live violation in the JS build (`js/config.js:141`,
  DUG-153). In Swift it simply never gets written.
- **Internal checkpoint scores never cross an API boundary.** PASS/FAIL only.
- **No test footage in git.** `media/` is gitignored for a reason. The clips are
  in `Design & UX/media/test-clips/pitch_01–06.mov` in the OneDrive folder.
  The test harness reads them from a path in an environment variable
  (`DUGOUT_CLIPS`) and **skips with a clear message** when unset. The clips are
  of a real child; they do not go into the repo, a gist, a paste, or a cloud
  artifact.
- **Do not edit or delete anything in `js/`.** It is the reference
  implementation until P1.4 passes.
- **No third-party SDKs.** AVFoundation, Vision, CoreMedia, Accelerate only.
- **No API key ships in the app**, ever.
- **The test must fail first** (DUG-92). Write the failing test, then the code.
- Branch per sprint off `main`, named for its ticket. `main` is currently
  `f79bce0`. Use `git -c core.fileMode=false` — the Cowork bridge mount flips
  the exec bit on everything otherwise.

## 7. What NOT to build in Phase 1

No SwiftUI views. No screens. No StoreKit. No camera capture (that is Phase 2).
No networking. No persistence beyond writing JSON to stdout or a file.

If a sprint seems to need one of those, it has been scoped wrong — stop and say
so rather than widening it.

## 8. A note on the author

Derell writes JavaScript, not Swift, and works about three hours a day. Write
idiomatic Swift and explain the unfamiliar parts in comments where they earn it
— `AVAssetReader` setup, `VNRequest` handling, concurrency. Prefer clear over
clever. He has to maintain this alone for a long time.

---

## As built — 2026-10-14 (DUG-159, branch `native/phase-1-pipeline`)

Derell's instructions for the first slice differed from this brief in places. Where they did,
his won. The brief's text above is left as written.

| Brief | Built | Why |
|---|---|---|
| `ios/DugOutKit/` | `ios/DugOutCore/` (+ `dugout-probe` CLI, as specified here) | Named by Derell |
| Per-frame output as JSON | CSV | Specified by Derell |
| App target depends on it in Phase 3 | Linked to `ios/DugOut.xcodeproj` now; nothing in the app calls it | Specified by Derell; proves it compiles for iOS 15 on every app build |
| Branch per sprint, named for its ticket | `native/phase-1-pipeline`, commits carry DUG-159 | Branch named by Derell |
| P1.2: mean and median | median / p10 / mean | p10 asked for by Derell |

Additions: a `ProbeOutput` target that holds the keypoint CSV writer so the app never links it;
the CLI refuses to write keypoints inside a git working tree or a cloud-synced folder; real-clip
tests fail (not skip) when `DUGOUT_CLIPS` is set but wrong.

Findings that change later sprints — read before P1.3: **CANON R-41** (the regression clips are
~8× slow-motion exports, so every time constant was tuned on playback time; ~7% near-repeat
frames) and **CANON R-42** (Vision pose result and what it does not prove). P1.1 also found that
every iPhone pitch clip opens with an empty edit, for which AVAssetReader emits one all-black
frame; `FrameReader` skips and counts it.
