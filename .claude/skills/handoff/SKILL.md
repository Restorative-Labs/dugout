---
description: Close out a DugOut session — append the session-log entry the next session reads, record any rulings in CANON, and leave open items in a form the next session can act on. Use at the end of a working session or when asked where things stand.
argument-hint: "[optional focus, e.g. 'segmentation' or 'store']"
allowed-tools: Read, Grep, Glob, Bash(git log:*), Bash(git status:*), Write, Edit
---

# Session handoff

A session that ends without a log entry and a commit did not happen.

## Do these

1. **Check the working tree.** `git -c core.fileMode=false status`. Quantify anything
   uncommitted — how many files, how many lines, which features. Uncommitted work is a
   blocker, not a footnote. Five weeks of it went unpushed once already.

2. **Record rulings in `docs/CANON.md`.** Anything decided this session that is a number or a
   rule gets a row: number, ruling, source, date, status. A ruling not in CANON did not happen.
   If a `CONTRADICTED` row was resolved, close it by fixing the code or the comment — never by
   deleting the row.

3. **Append to `docs/SESSION-LOG.md`**, newest at the top:

```
## YYYY-MM-DD — <what this session was about>
Tickets: DUG-xx
Changed: <files / what landed>
State: <committed+pushed | branch open | uncommitted>
Next: <the one thing the next session should pick up>
```

4. **Name what is still unproven.** Every open item carries what would falsify or confirm it,
   and what evidence is missing. "Needs a device confirm on original H.264" is a usable
   handoff; "needs testing" is not.

5. **Commit and push.**
