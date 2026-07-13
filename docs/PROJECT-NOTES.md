# Dugout — Project Notes

**Module:** Hitting · Film Room (v1)
**Org:** Restorative Labs · Repo: `Restorative-Labs/dugout` · Live: https://restorative-labs.github.io/dugout/

## What's in this folder

| Path | What it is |
|---|---|
| `index.html` | The entire app — one self-contained file, no build, works offline. GitHub Pages serves this at the root URL. |
| `README.md` | Public-facing repo readme with features + roadmap |
| `.nojekyll` | Tells GitHub Pages to serve files as-is |
| `media/swing-shadow.mp4` | The processed shadow-silhouette swing video (source for the checkpoint animations; also usable as a Compare reference clip) |
| `media/shadow-sprite.jpg` | 130-frame sprite sheet (10×13 grid, 288×191 per frame, 12fps) baked into index.html — kept here as the editable source asset |
| `docs/PROJECT-NOTES.md` | This file |

## App features (v1)

1. **Film** — record/load a swing, ¼/½ speed, frame stepping
2. **Chalk kit** — lines, arrows, circles, measured angles drawn on frozen frames
3. **Checkpoints** — 6 cards (Stance → Load → Stride → Hips Fire → Contact → Finish); each plays the real shadow swing, slowing + highlighting its phase with always-on coaching lines
4. **Compare** — two clips side-by-side, per-clip frame nudge, synced playback
5. **AI Coach** — samples 8 frames from a marked swing window; returns one fix, dad-voice + kid-voice guidance, a drill, and on-film annotations (Claude-hosted version only)
6. **Scouting notes** — persists locally

## Shadow pipeline (how the media was made)

Source clip → 130 sampled frames → dual segmentation (u2net_human_seg ∪ isnet-general-use) → largest-connected-component filter (kills background bleed) → bat gap-fill by geometric interpolation where detection dropped → neighbor-frame de-flicker → composite on Dugout dusk background → sprite sheet. Playback cross-fades adjacent frames to smooth residual motion.

## Phase windows (seconds into the shadow clip)

Stance 0–1.6 · Load 1.6–3.2 · Stride 3.2–4.2 · Hips 4.2–5.0 · Contact 5.0–6.8 · Finish 6.8–end

## Roadmap

- v1.x: AI coach behind a small backend (API key) so the public demo gets analysis
- v2: Pitching module (dad's home turf) — same film-room chassis, new checkpoints
- v3: Catching, infield; per-player film history
- Platform: AAU team accounts, position-by-position skills tracking, coach dashboards, minor-safe privacy model
