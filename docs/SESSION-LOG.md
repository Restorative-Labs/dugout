# DugOut — session log

One entry per session, newest at the top. Read this after `CLAUDE.md` at the start of every
session. A session that ends without an entry here and a commit did not happen.

Format:

```
## YYYY-MM-DD — <what this session was about>
Tickets: DUG-xx
Changed: <files / what landed>
State: <committed+pushed | branch open | uncommitted>
Next: <the one thing the next session should pick up>
```

---

## 2026-10-14 — Film tab fix (DUG-40), then native Phase 1: real timestamps and Vision pose
Tickets: DUG-40, DUG-156 (not started), DUG-158 (epic, filed), DUG-159 (filed)
Changed: **Branch `DUG-40-film-controls`** (`643c364`, pushed, off `DUG-106-bundle-id`):
the checkpoint chips get their own row above the transport; scrub / step-play-step / speed rows
≥ 44pt; the swing bar moves above the stage; the right rail wraps on short screens; the frame is
capped to the stage height. Verified headless at 320×568, 375×667, 440×956 (zero overlaps); the
original layout reproduced the bug exactly. Installed on Derell's phone — **device check not
yet reported**. **Branch `native/phase-1-pipeline`** (off `main` `f79bce0`): `ios/DugOutCore`
Swift package (library + `ProbeOutput` test-only target + `dugout-probe` CLI + 11 tests),
linked to `ios/DugOut.xcodeproj`; `docs/CANON.md` R-40/R-41/R-42; `docs/NATIVE-P1.md`
committed with an "As built" appendix. Nothing in `js/` touched.
State: committed+pushed on both branches; neither merged. `DUG-106-bundle-id` still unmerged.
Left untouched and uncommitted: `design/canvas/*.py` (another session's DUG-157 edits).
Next: **Derell confirms the regression clips were filmed in Slo-mo (R-41)** and films one
normal-speed swing — every time constant P1.3 transfers from `config.js` depends on the answer.

**Native ruled today (R-40).** Tonight was P1.1 + P1.2 only — no UI, no segment/evaluate port.
Tests written first and seen failing (DUG-92), twice: the first slice, and the fixes below.

**P1.1 — the timeline is trustworthy, with one trap.** Monotonic on every clip. `Three Swings`
is H.264 1280×720, 2,485 frames, every gap 33.333 ms. The pitch clips are HEVC 1920×1080 and open
with an **iPhone empty edit (0.188–0.204 s)** for which AVAssetReader emits one **all-black frame
at t=0** with no marker — it would have been fed to Vision and, in P1.3, to motion sampling.
Now skipped and counted. The 133 ms gap before `pitch_01`'s last frame is real (in the file).

**P1.2 — Vision sees the wrists (R-42).** Person found in 100% of camera frames on all 7 clips;
wrist medians 0.76–0.83, elbows 0.80–0.85, no crop. But at contact the far-side arm drops —
`Three Swings` @31.58 s left elbow 0.184. Fair claim: at least as good as the two-pass MoveNet
the app ships, clearly better than single-pass; **not** "0.8 vs 0.3", because the scales differ
and the 0.3 is 8 values from an unnamed clip whose probe code was never kept.

**The finding that matters most (R-41).** The verification pass found the regression clips are
**~8× slow-motion exports** (Apple's slo-mo flag on `Three Swings`; audio band-limited to
~2.7 kHz). Every timestamp, every "swing lasts 0.1–0.2 s", every `*_SEC` constant and the
per-frame spike threshold were measured in playback time on slowed footage. Nothing in the repo
said so. ~7% of frames are also near-repeats behind perfectly even timestamps.

**How it was checked.** A 29-agent adversarial verification: independent recompute of all 132
table cells from the CSVs (0 hard mismatches), orientation proved on synthetic clips, keypoint
plausibility without viewing a frame, MoveNet comparability, compliance. Its upheld defects were
fixed test-first: the black filler frame; the keypoint CSV writer compiled into the shipped app
(moved to `ProbeOutput` — 0 symbols in the Release binary now); CSV precision; a repo guard that a
symlink or case-variant path could bypass (now also refuses cloud-synced folders); real-clip
tests that skipped green when `DUGOUT_CLIPS` was wrong. Pose CSVs (biometric) live only in the
session scratchpad, never in the repo.

---

## 2026-10-08 — main fast-forwarded to the rescue branch; Pages unfrozen
Tickets: DUG-34, DUG-38 (the swing-gate fix reaches Pages); R-37, R-38, R-39 committed
Changed: `2ea48c4` on `rescue/jul-field-tuning` — `docs/CANON.md` (R-37 through R-39),
`docs/SESSION-LOG.md`, and the untracked `design/canvas/` (the generator that rebuilds the
screen canvas). `main` fast-forwarded `c259f05..2ea48c4` (`--ff-only`, ancestry verified
first) — 6 commits, 39 files, +4394/−50. Branches `session-based-capture` and
`rescue/jul-field-tuning` deleted, local and remote, each after verifying 0 commits outside
`origin/main`. Repo now carries `main` only.
State: committed+pushed (this entry lands as its own commit on `main`).
Next: **the device confirm on original H.264** — `Three Swings.mov` (3) and `pitch_01.mov`
(2) on the iPhone, against the build now on `main`. Derell's; not run this session.

**What the merge fixed.** `main` had been frozen at `c259f05` since **25 July**, and that
commit carries `SPIKE_ENTER_MULT: 3.0`. Real swings measure 2.3–3.0x baseline, so the demo
Pages served for ten weeks — the one shown to trainers — found **zero swings**, and the July
fallback against zero-swing rounds hid it. The merge is what puts `2.4` live. Deployed
`js/config.js` fetched with `no-store` reads `SPIKE_ENTER_MULT: 2.4`.

**Unproven, stated plainly.** The zero-swing finding and the 2.4 candidate were both measured
headless on VP9 webm remuxes. Nobody has confirmed on device that the live build finds 3 and 2
swings. Until that run, "the demo finds swings" is not a publishable claim — the device confirm
is what would falsify it.

**Pages verification** (live URL, 375×812, after build `2ea48c4` reported `built`):
HTTP 200, 23 resources all 200, **zero console messages, zero failed requests, one origin**
(`restorative-labs.github.io`). Fonts serve from `css/fonts/`, TF.js from `vendor/`. The MoveNet
model is not fetched at boot, so this run did not exercise it.

**Noted, not changed:** `design/canvas/screens.py` writes a Google Fonts `<link>` into the
canvas HTML it generates. It is a design tool — not loaded by `index.html`, not bundled by
Xcode — so invariant #2 holds for the app, but don't copy that pattern into `css/` or `js/`.
Also: this log had drifted out of newest-first order (09-08 sits above 09-12/09-13). Left as is.

---

## 2026-09-08 — TestFlight prep: org team, export compliance, and the swing-gate fix
Tickets: DUG-34, DUG-38
Changed: `js/config.js` (SPIKE_ENTER_MULT 3.0 -> 2.4), `ios/DugOut.xcodeproj/project.pbxproj`
(DEVELOPMENT_TEAM -> the LLC, build number 1 -> 2), `ios/DugOut/Info.plist`
(ITSAppUsesNonExemptEncryption), `ios/README-IOS.md` (stale free-account notes).
State: committed+pushed on `rescue/jul-field-tuning`. `main` still untouched.
Next: in Xcode under the LLC account — register the bundle id on the org team, let Xcode
issue the Apple Distribution cert, Archive and upload. Then confirm swing detection on the
phone before this branch goes near `main`.

**The segmentation blocker is fixed.** `SPIKE_ENTER_MULT` 3.0 -> 2.4. Both regression clips
now return the right count, stable over four runs:

| Clip | Expected | Found | Contacts | Ground truth |
|---|---|---|---|---|
| `Three Swings.mov` | 3 | **3** | 4.27 / 31.58 / 57.29s | ~4.3 / 31.6 / 57.3 |
| `pitch_01.mov` | 2 | **2** | 7.43 / ~20.1s | 7.43 confirmed |

Counts are stable. Contact timing is exact and repeatable on audio-confirmed swings
(4.27 / 31.58 / 57.29 and 7.43 repeat to the hundredth); on swings with no ping it falls
back to the motion peak and drifts run-to-run by up to ~0.8s. That is the designed
behaviour, not a defect, but it is why the phase map wants the audio channel.

The old `MAX_SPIKE_MULT` comment claiming real swings run "3-8x" was wrong — measured
2.3-3.0x on both clips — and that wrong number is what set the enter gate above the real
signal. Comment corrected in place so the next tuning pass does not repeat it.

**Apple account — the project was signing under the wrong team.** Membership is
**Restorative Labs LLC, Team `NKNR8F3VKC`, Organization, paid through Aug 19 2027**. The
project had `DEVELOPMENT_TEAM = KX2L3Q37G7`, the free personal team (the local cert reads
`OU=KX2L3Q37G7, O=Derell Jenkins`), which is why no Apple Distribution certificate existed
and why signing kept expiring every 7 days. Repointed to `NKNR8F3VKC`.

**Verified:** `xcodebuild ... archive` succeeds and passes `-validate-for-store`; the built
bundle carries bundle id `com.restorativelabs.dugout`, version 1.0 build 2,
`ITSAppUsesNonExemptEncryption=false`, the tuned `config.js`, and all web resources
including the 7 self-hosted woff2 faces. 6.9MB.

**Still open before an App Store submission (not blockers for TestFlight):**
`TARGETED_DEVICE_FAMILY` is still `"1,2"` — the app ships to iPad with an iPhone-viewport
layout; set to `"1"` if iPad is not intended. `js/ai.js` pins `MODEL = 'claude-sonnet-4-6'`,
which does not look like a current model id and would fail for any tester who enters a key.
A privacy policy URL is required for external TestFlight testers, and the app films minors.

---

## 2026-09-04 — Landed the five weeks of July work in three commits
Tickets: DUG-34, DUG-39, DUG-40, DUG-42
Changed: three commits on `rescue/jul-field-tuning`, nothing merged to `main`.
1. DUG-34 segmentation field tuning — `js/config.js`, `js/segment.js`, `docs/POSE-PROBE.md`,
   `docs/PROJECT-NOTES.md`. 2. Film Space v2 / onboarding rules / self-hosted fonts —
   `index.html`, `css/shell.css`, `css/fonts/` (7 woff2), `js/filmshell.js`, `js/shell.js`,
   `js/app.js`. 3. Repo hygiene — `CLAUDE.md`, `.gitignore`, `scripts/`, and the four new
   `docs/` files.
State: committed+pushed on the branch. `main` untouched.
Next: decide `SPIKE_ENTER_MULT` — see the regression result below. It is the one thing
standing between this branch and a merge.

**Verified this session:**
- Headless boot at iPhone viewport, repo served locally: zero console errors, zero page
  errors, zero failed requests, zero non-local requests. All 18 asset refs and all 7 font
  URLs in `index.html` resolve. Invariant #2 now holds in the committed tree, not just on
  local disk.
- Cleared a **0-byte `.git/index.lock` dated Jul 29 10:14** — a crashed git from the July
  session, with no git process running. Plausibly part of why this work never got committed.
- SharePoint metadata scan clean (the only hits are `CLAUDE.md` and `SEGMENTATION-TDD.md`
  describing the check itself).

**Regression result — the branch does not yet find swings (open):**
Ran the real clips through `DugoutSegment.segment()` in headless Chrome, repeatedly.
As committed, **both regression clips return 0 swings**:

| Clip | Expected | `SPIKE_ENTER_MULT` 3.0 (as committed) | at 2.4 |
|---|---|---|---|
| `Three Swings.mov` | 3 | **0** | **3** — contacts 4.27 / 31.58 / 57.29s |
| `pitch_01.mov` | 2 | **0** | **2** — contacts 7.43 / 20.55s |

At 2.4 the contacts match the audio ground truth (~4.3 / 31.6 / 57.3s) to within 0.03s, and
swing 1 of `pitch_01` lands on 7.43s — the exact figure the July comment in `segment.js`
records. So the pipeline, the footage decode, and all five tuned constants are working; the
clips are being read correctly.

The cause is **not** in this diff. Real swings measure **2.3-3.0x baseline** on both clips,
but `SPIKE_ENTER_MULT` demands **>3.0x**, so nothing ever enters a span. Confirmed by
isolation: forcing the old fixed 5-frame smoothing also returns 0 at 3.0, so the time-based
smoothing change is exonerated. `SPIKE_ENTER_MULT: 3.0` is untouched by this branch — it is
older, and the comment beside `MAX_SPIKE_MULT` claiming real swings run "3-8x" is what the
measurements now contradict.

Left as-is deliberately: lowering it changes tuning beyond what this session was asked to
land, and it wants a device confirm plus the other four `pitch_0*.mov` clips before being
called right. 2.4 is the measured candidate — it cleared both clips with margin on either
side (highest real swing 2.98x, so 3.0 misses by a hair).

---

## 2026-09-13 — Apple identity created; the bundle-ID blocker is gone
Tickets: DUG-51 next; DUG-123 confirmed by Apple at registration
Changed: `docs/CANON.md` — R-36 promoted to RULED AND ENFORCED, Apple state table added,
R-38 recorded.
State: uncommitted along with all CPO work since 09-04.
Next: **DUG-51** — Paid Apps agreement, tax, banking, Small Business Program. Now the sole
remaining gate on October revenue. Also decide EU availability (R-38) before the availability
step.

**Registered** `com.restorativelabs.dugout-ios` under `NKNR8F3VKC` with Sign In with Apple as
the only capability, then created the App Store Connect record as **Dugout: Next Rep**
(iOS, en-US, SKU `DUGOUT-IOS-001`). Apple accepted the name at save, which is first-party
confirmation the title is free — R-36 is now enforced, not merely ruled.

**R-31 vindicated.** The whole chain took under twenty minutes and never needed support case
102956802933, which Apple had escalated to senior support with no ETA. Treating an invisible
string as a gate would have cost weeks of the October window.

**Two findings surfaced during the work:**
- **R-38** — EU Digital Services Act trader status is a *submission gate* for new apps, absent
  from every existing doc. Recommend excluding the EU at v1.
- Apple's own registration screen flagged that Sign in with Apple needs Private Email Relay
  domain and email-source registration to function — independent confirmation of DUG-123.

**Automation note:** App Store Connect's New App dialog resists automation — its Primary
Language and Bundle ID selects ignore both programmatic values and keyboard selection. Text
fields and checkboxes are fine. Expect to hand those two fields to Derell on any future run.

---

## 2026-09-12 — Store listing name settled: Dugout: Next Rep
Tickets: the App Store submission chain
Changed: `docs/CANON.md` — R-36 ruled, R-35 superseded, R-32 already superseded.
State: uncommitted along with the CPO work from 09-04 and 09-08.
Next: register `com.restorativelabs.dugout-ios`, create the App Store Connect record as
**Dugout: Next Rep** / subtitle **Hitting: one fix every round**. Fallbacks in order if Apple
rejects: `Dugout: Swing Check`, `Dugout: Cage Work`.

**Three rulings to land one name.** R-32 (Film Room) collided with GameChanger's own feature.
R-35 (Dugout Hitting) was safe and said nothing. R-36 came from Derell's framing — *the app is
designed on feedback loops* — which is a better articulation of the product than anything the
CPO had offered. "Next Rep" is the loop as an action, it is what a coach says out loud, and it
is forward-looking rather than diagnostic, which aligns the name with R-02 (never show a score).

**Process fix applied:** clearance ran *before* the ruling this time — market leaders first,
then exact-string, then adjacent categories. Accepted caveat recorded rather than buried:
"NextRep" is crowded in fitness (4 iOS apps), which is a different risk class from a category
king owning the phrase.

---

## 2026-09-08 — App Store launch handoff absorbed; bundle ID unblocked
Tickets: DUG-51 (Apple agreements) and the App Store submission chain
Changed: `docs/CANON.md` — R-31 through R-34 plus a competitive correction.
State: uncommitted along with the 2026-09-04 CPO work.
Next: register `com.restorativelabs.dugout-ios`, create the App Store Connect record, then
re-sequence the Jira dates.

**The unblock:** the incoming handoff treated Apple support case 102956802933 — asking Apple to
release `com.restorativelabs.dugout` from the personal team `KX2L3Q37G7` — as the gate on
everything. It is not. A bundle ID is invisible to users, nothing is on TestFlight, and no
config is keyed to it, so the migration cost is zero while the case has no SLA. **Register a
new ID today** (R-31); keep the case open as cleanup.

**Competitive correction:** "Dugout App" was described as a real functional competitor shipping
AI swing analysis. Verified — it is a TeamSnap/GameChanger competitor whose subtitle is "Team
Management for Everyone," where AI video analysis is one bullet between Digital Trading Cards
and Walkup Songs, with too few ratings to display an overview. Name collision, feature overlap,
not a competitor. The real dedicated field is WIN Reality, V1 Baseball, b4-app and Baseball AI
— none of which was in `competitive-landscape.md`.

**Name finding:** the "Dugout" namespace holds at least seven live apps (Dugout App, Dugout
Genius, Dugout Analytics, DugoutIQ, Prospect Dugout, Dugout 360, Dugout Dude). "Dugout" is a
commodity noun in this category. Ruled **Dugout: Film Room** as the listing title (R-32), with
the home-screen name staying **DugOut** (R-33).

---

## 2026-09-04 (later) — CPO role established; five business decisions ruled
Tickets: DUG-13, DUG-25, DUG-36, DUG-66, DUG-70 (all previously parked in Needs Business Decision)
Changed: `docs/CANON.md` created — the ruling ledger, 30 entries. `.claude/rules/`
(checkpoints, visibility, privacy, segmentation — auto-load by path), `.claude/skills/`
(premise, ticket, handoff), `.claude/settings.json` (permission gates). CPO charter added to
`CLAUDE.md`. Mirrored to the Claude project as `canon.md`, `repo-claude-md.md`, and a rewritten
`current-status.md`.
State: **uncommitted** — 8 new files under `.claude/`, plus `docs/CANON.md`, plus edits to
`CLAUDE.md` and this file. Nothing committed by this session.
Next: commit the above; then Derell reviews R-26 through R-30 and overrides anything he
disagrees with; then re-sequence the Jira dates, which depend on those rulings.

**Ruled (full reasoning in CANON):**
- R-26 pricing — $99/yr or $14.99/mo, one tier, no free tier. Ruled but **not publishable**
  until StoreKit enforces it; the `$99/yr` in the mockup stays internal-only.
- R-27 backend — none before November; then one Next.js app, one Postgres, no Clerk.
- R-28 storage — sync OFF by default; R2-vs-S3 deferred to November on purpose.
- R-29 philosophy — four verbs only: pick, order, ban, rename.
- R-30 COPPA — drop the self-serve 13–17 tier; pose keypoints are biometric.

**The system's first catch:** the screen-flow mockup renders `Player · $99/yr` and a renewal
date while DUG-25 had ruled nothing. Logged as R-16. Under the publishable test that number
was never eligible to leave the building, and would not have been caught by review.

---

## 2026-09-04 — Workspace repair: paths, docs, and five weeks of unlanded work
Tickets: —
Changed: `CLAUDE.md` rewritten (correct absolute paths, doc map, surface-split rule,
`core.fileMode` fix, this ritual). `docs/` gained `SYSTEM-TDD.md`, `SEGMENTATION-TDD.md`,
`VLM-PLAN.md` — moved out of the assets workspace so engineering docs version with the code.
Created this log.
State: repo moved out of OneDrive to `/Users/derelljenkins/code/dugout`; `core.fileMode`
set to false; branch `rescue/jul-field-tuning` created and pushed. Claude Code 2.1.261
installed. The July work is still uncommitted on that branch.
Next: land the 12 modified files (414 insertions) — DUG-34 field tuning, gate v2, Film
Space v2, self-hosted fonts — plus this log and the three docs. Then verify against
`Three Swings.mov` / `pitch_01.mov` on device before merging to `main`, because Pages
serves `main` and this code has not been re-checked since July.

**Found this session:**
- `CLAUDE.md` claimed the repo was at `~/code/dugout`. It was not; it was inside OneDrive,
  and `~/code` held only the `restore-*` repos. Every session began from a false path.
- The repo — `DugOut.xcodeproj` included — sat inside OneDrive CloudStorage.
- Twelve files carried real uncommitted work dated 2026-07-26, unpushed for five weeks.
  It includes the fix for the July shimmer failure that the Segmentation TDD still describes
  as open: `BALL_PIXEL_DELTA: 26` / `BALL_MIN_AREA: 4` (cut noise ~8x from the 1,810-track
  saturation), `BALL_MAX_TRACKS: 80` (cage footage produced 43 *real* tracks and the old cap
  of 40 discarded all of them), `MOTION_SMOOTH_SEC: 0.24` (the fixed 5-frame window assumed
  30 samples/sec; rVFC at 4x delivers ~7.5, which erased a real 0.2s swing), and
  `AUDIO_CONFIRM_SEC` 0.35 → 0.75.
- `CLAUDE.md` and `css/fonts/` were untracked. The seven self-hosted woff2 files and the
  `@font-face` block in `index.html` are both uncommitted — consistent, so Pages is not
  404ing, but invariant #2 is only satisfied on Derell's disk, not in the shipped build.

---

## 2026-07-25 — UX v2 + Film Space v2
Tickets: DUG-39, DUG-40
Changed: native shell, onboarding + roles, You area, checkpoint drill-in, Team board.
Commits `c4d1b6f`, `d9e9677`, `c259f05`.
State: committed+pushed. Both tickets sat in QA awaiting a device confirm.
Next: (unrecorded at the time — the session log did not yet exist)
