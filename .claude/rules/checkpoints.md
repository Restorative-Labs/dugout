---
paths:
  - "js/{evaluate,config,app,library}.js"
---
# The six checkpoints — how to work here

**No threshold appears in this file on purpose.** Every number lives in `js/config.js` and is
logged in `docs/CANON.md` with its source. Prose must never be able to disagree with config —
R-14 is what that costs.

## Before changing anything here

1. **Stance, Load, Stride, Hips Fire, Contact, Finish.** Six, in that order, always. They are
   the rubric, the tip-library index, and the philosophy structure at once. Adding a seventh
   is not a feature — it is a schema change across three systems.
2. **The internal score never leaves.** PASS/FAIL is the entire user-visible vocabulary
   (R-02). Not in a tooltip, not in a debug panel a user can reach, not in an API response.
   If you are about to render a number, stop.
3. **`PHASE_WINDOWS` are fractions of the swing window, anchored on `CONTACT_ANCHOR`.** They
   are only meaningful if contact actually lands at that anchor. It currently does not
   (R-15 / DUG-54). Any work that reads a phase window is standing on that defect.
4. **The tip library is closed** (R-06). The app never invents a fault, a cue, or a drill.
   `js/library.js` is generated — never hand-edit it.

## The test that counts

A checkpoint change is proven against the ground-truth clips, not against reasoning.
`Three Swings.mov` (3 swings, contacts ~4.3 / 31.6 / 57.3s) and `pitch_01.mov` (2) are the
regression pair. Run it more than once — this pipeline has produced flaky results before.
