---
paths:
  - "js/{segment,pose,config}.js"
---
# Segmentation — how to work here

This pipeline has failed in the field twice and both failures were invisible to the tests that
existed. Treat every constant here as unproven until it is measured.

## Standing state (see docs/CANON.md)

- **R-14 CONTRADICTED** — `SPIKE_ENTER_MULT` has no headroom above the real distribution.
- **R-15 CONTRADICTED** — contact does not land at `CONTACT_ANCHOR` (DUG-54).
- **R-21 PROVISIONAL** — the two peak→ping measurements in `config.js` disagree.

## Rules

1. **Never tune a constant from one clip.** Both prior failures came from a value that was
   correct on the clip in front of the person who set it. The fixture corpus is the blocker;
   say so rather than working around it.
2. **Headless numbers are proxy numbers.** Chromium has no H.264, so verification runs on a
   VP9 remux — and motion energy *is* inter-frame delta, which a codec pass changes. A
   headless measurement can diagnose a problem; it cannot ratify a threshold. Device
   confirmation on the original file is required before any motion constant is ruled.
3. **A model can only confirm a candidate, never find one** (R-25). Detection is
   deterministic and on-device, permanently. Do not design around a future model that finds
   swings in video.
4. **Zero swings is a signal, not an edge case.** A fallback that prevents a round from
   returning zero can mask the real cause — it has already done so once.
