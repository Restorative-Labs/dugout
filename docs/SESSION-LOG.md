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
