---
description: Run one DugOut ticket end to end — premise check, restate the criteria, implement diff-scoped, prove it against the ground-truth clips, then hand back. Use when starting work on a DUG ticket or when asked to take the next ticket.
argument-hint: "[DUG-###]"
disable-model-invocation: true
---

# Run a DUG ticket

## 1. Premise
Run the `premise` skill against the ticket **before** reading its acceptance criteria as
truth. If CANON marks the ground `CONTRADICTED`, report that instead of proceeding.

## 2. Restate
Say back, in one paragraph, what "done" means — in terms of observable behaviour, not files
changed. If you cannot state it observably, the ticket is not ready.

## 3. Implement, diff-scoped
Touch only what the ticket names. A drive-by fix in an adjacent file is a separate ticket;
file it rather than folding it in. Branch name and commit subject both carry the DUG key.

## 4. Prove it
Per `CLAUDE.md` §Verification — all of it, not the convenient parts:
- headless boot at iPhone viewport, external network blocked, zero errors and zero failed
  requests, or every one explained
- every asset reference in `index.html` resolves
- external network references still number zero
- **segmentation changes run against `Three Swings.mov` and `pitch_01.mov`, more than once**
- SharePoint metadata scan

State plainly which checks you ran and which you could not. A skipped check is reported, never
assumed to pass. **A headless motion measurement is a proxy — it diagnoses, it does not ratify.**

## 5. Hand back
Run the `handoff` skill. Record any ruling in CANON. Never merge to `main` — Pages serves it.
