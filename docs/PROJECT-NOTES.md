# Dugout — Project Notes

**Module:** Hitting · Film Room (v1)
**Org:** Restorative Labs · Repo: `Restorative-Labs/dugout` · Live: https://restorative-labs.github.io/dugout/

## What's in this folder

| Path | What it is |
|---|---|
| `index.html` | App shell + view markup. Was one 354KB self-contained file; now ~25KB, with css/ and js/ split out. Still no build step — GitHub Pages serves it as-is. |
| `css/app.css` | The v1 styles, extracted verbatim |
| `css/session.css` | Round Card, progress, philosophy, capture |
| `js/config.js` | Every tunable constant: caps, thresholds, phase windows, age gates |
| `js/library.js` | **Generated** — the Tip Library. Do not hand-edit; see `scripts/build_library.py` |
| `js/store.js` | Profiles/sessions/philosophy in localStorage; keyframes in IndexedDB |
| `js/pose.js` | MoveNet wrapper, two-pass (detect → crop → re-detect) |
| `js/segment.js` | Round segmentation: motion energy + audio confirm |
| `js/evaluate.js` | The 18 detectors, the rollup, and verbal-first rendering |
| `js/ai.js` | The single AI adapter — one call per session, stub fallback |
| `js/filmroom.js` | The v1 film room + the keyframe player. Holds the inlined shadow sprite |
| `js/app.js` | Router, round pipeline, Round Card, progress, philosophy |
| `vendor/` | TF.js + MoveNet, vendored (~5.6MB). No CDN, no build, works offline |
| `scripts/` | `build_library.py` (xlsx → js), `build_index.py` (assembles index.html) |
| `docs/POSE-PROBE.md` | Measured findings that drove the design — **read before tuning thresholds** |
| `media/*` | Editable source assets (also at repo root, historically) |

## Regenerating

The Tip Library is generated from `DugOut_Tip_Library_Seed_v0.2.xlsx` in the working
folder. After the trainer revises the sheet:

    python3 scripts/build_library.py

Never hand-edit `js/library.js` — it will be overwritten.

## App features (v2 — session-based)

1. **Rounds** — upload a cage/BP video or record in-app; auto-segmented into swings,
   capped at 90s / 15 swings; the raw upload is released and never persisted
2. **Round Card** — priority focus + verbal correction first, six ✓/✗ checkpoint marks
   (no numbers anywhere), swing reel, best-swing highlight, per-swing Deep Dive
3. **Checkpoints** — the same six cards, now the spine of the rubric, the library index,
   and the philosophy structure
4. **Progress** — per-checkpoint streaks and trend arrows across rounds (ER-12)
5. **My Philosophy** — pick a school preset, adjust tips, order priorities, mark red
   lines, add your own slang. Selection, not authoring. Renders all feedback.
6. **Film room** — the v1 tools: chalk kit, compare, Film Review (renamed from "Coach's
   film session"), scouting notes
7. **AI Coach** — one call per session for wording only; Deep Dive is per-swing on demand
   (Claude-hosted version; the static demo composes everything from the library)

## What is honestly detected

Of the library's 28 fault entries (FN-04 is a philosophy toggle, not a fault), pose can
measure 18. The rest need ball flight or bat tracking and are **never guessed at** — a
checkpoint is scored only on what can actually be measured. Every checkpoint retains
detectable entries, so all six are still graded. The concentrated gap is the outcome-based
Contact faults (CT-01/02/03/04) and anything defined on the barrel (FN-01, CT-04).

## Shadow pipeline (how the media was made)

Source clip → 130 sampled frames → dual segmentation (u2net_human_seg ∪ isnet-general-use) → largest-connected-component filter (kills background bleed) → bat gap-fill by geometric interpolation where detection dropped → neighbor-frame de-flicker → composite on Dugout dusk background → sprite sheet. Playback cross-fades adjacent frames to smooth residual motion.

## Phase windows (seconds into the shadow clip)

Stance 0–1.6 · Load 1.6–3.2 · Stride 3.2–4.2 · Hips 4.2–5.0 · Contact 5.0–6.8 · Finish 6.8–end

## Roadmap

- Verify on a real phone: the playback+rVFC segmentation path, the timed round, and chalk
  over stored keyframes (see docs/POSE-PROBE.md — the preview sandbox cannot show these)
- Trainer validation of the library, then re-run `scripts/build_library.py`
- Bat tracking would unlock CT-04 and FN-01, and sharpen Contact considerably
- AI coach behind a small backend so the public demo gets analysis
- v2: Pitching module — same film-room chassis, new checkpoints
- v3: Catching, infield; per-player film history
- Platform: AAU team accounts, coach dashboards, minor-safe privacy model
  (out of scope now; the data model already carries profileId everywhere)
