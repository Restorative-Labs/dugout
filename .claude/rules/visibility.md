---
paths:
  - "js/{shell,filmshell,filmroom,app}.js"
  - "index.html"
---
# Who can see what — how to work here

The permission model is a **product invariant, not a preference.** It is the thing that makes
DugOut sellable to a parent of an 11-year-old.

## The rules

1. **A coach never has access to raw video** (R-03). Results only: pass/fail marks, the
   priority focus, the swing reel. If you are adding a surface for a coach and it can reach a
   clip, the surface is wrong. A "Film" tab has appeared in a coach mockup once already and
   was caught in review — it is an easy mistake because the parent shell has one.
2. **Philosophy is selection, never authoring** (R-05). A coach picks tips, orders them, bans
   cues, and maps his own slang onto library tips. He cannot invent a fault, write a new tip,
   or remove a safety rail through any screen.
3. **A parent grants visibility; it is never assumed.** The default for a new athlete is
   private, no coach linked.
4. **Raw session video never leaves the device** and is deleted at segmentation (R-04). No
   feature may create a second copy — including a storage or sync feature (see R-18).

## Before you build a coach-facing screen

Name, out loud, every field it renders and where each one comes from. If any path leads back
to a clip, stop and say so rather than filtering it in the view.
