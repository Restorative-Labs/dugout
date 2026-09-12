---
description: Verify the premise before building anything on DugOut — reconcile ticket vs CANON vs config vs code, confirm every number has a measured source, and stop if the ground is wrong. Use before starting any DUG ticket, before trusting a figure, and before ratifying any constant.
argument-hint: "[DUG-### or the number/claim to check]"
allowed-tools: Read, Grep, Glob, Bash(git log:*), Bash(git grep:*), Bash(git show:*)
---

# Premise check

DugOut fails quietly and keeps rendering plausible output. This check exists to make the
silent things loud **before** work is built on them.

## Run these in order

1. **Read `docs/CANON.md`.** Is the thing you are about to trust listed? Note its status.
   A `CONTRADICTED` or `PROVISIONAL` row means you are standing on known-bad ground — say so
   before proceeding, do not route around it.

2. **Find the number in `js/config.js`.** If it appears in prose but not in config, the prose
   is a second configuration and must be deleted or reduced to a pointer. If it appears in
   both and they differ, **the code wins and the doc is the bug.**

3. **Ask where the number came from.** Every constant in `config.js` should trace to a
   measurement on real footage. Check the comment beside it. If the comment cites one clip,
   treat the value as unproven — both prior field failures were values correct on the single
   clip in front of whoever set them.

4. **Separate diagnosis from value.** "This gate has no headroom" and "it should be 2.4" carry
   different evidence bars. State which you have.

5. **Check the measurement's provenance.** A headless number is a **proxy** number: Chromium
   has no H.264, so verification runs on a VP9 remux, and motion energy *is* inter-frame delta.
   Headless can diagnose. It cannot ratify a motion constant.

6. **Read the ticket against the code.** Does the ticket describe behaviour the code actually
   has? Is the Jira key in the ticket the key in the commits?

## Stop conditions

Stop and report rather than continue if: CANON marks the ground `CONTRADICTED`; a number has
no measured source; a ticket's premise disagrees with the code; or the work needs a fixture
corpus that does not exist. **The disagreement is the finding.** Report it as the result.
