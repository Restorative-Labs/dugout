# DugOut — repo conventions for Claude sessions

Read this before touching anything. It carries the Restorative Labs engineering standard
plus the invariants specific to this codebase.

Tracking: Jira project **DUG**. Sole operator: **Derell**. There is no one else to review,
assign, or hand off to — never route work through another name.

---

## Paths — these are real, do not guess

| | Location |
|---|---|
| **This repo** | `/Users/derelljenkins/code/dugout` → `github.com/Restorative-Labs/dugout` |
| **Pages** | `restorative-labs.github.io/dugout` |
| **Assets workspace** | `/Users/derelljenkins/Library/CloudStorage/OneDrive2-RestorativeLabsLLC/Restorative Labs - Documents/04 — Dugout` |

The repo lives on local disk, **never inside OneDrive**. Media, the tip-library spreadsheet,
business and legal documents live in the assets workspace and are never committed here.

> Until 2026-09-04 the repo was physically inside OneDrive while this file claimed it was in
> `~/code`. If you find a `dugout/` directory under the assets workspace, it is a leftover —
> stop and tell Derell rather than working in it.

---

## Which surface is this work on?

**Does it produce a git diff?**

- **Yes → Claude Code, opened at `/Users/derelljenkins/code/dugout`.** Code, tests, build
  scripts, the Xcode wrapper, the TestFlight lane. Cheap context, sees the whole tree, can
  run `xcodebuild` and `fastlane`.
- **No → a Cowork session.** Jira, App Store Connect, the browser, Figma, legal drafts,
  unit economics, mockups, research. The connectors are the point and none exist in a terminal.

Jira is the handoff. A ticket is picked up in the terminal on a branch named for it and
closed from a Cowork session.

---

## Where every document lives

**In this repo, under `docs/` — versions with the code, read by both surfaces:**

| File | What it is |
|---|---|
| `docs/SYSTEM-TDD.md` | End-to-end technical design: data flow, identity, email, security |
| `docs/SEGMENTATION-TDD.md` | Swing boundaries, counting, checkpoint registration. Carries **DUG-54** |
| `docs/VLM-PLAN.md` | Between-swings feedback, the 1 FPS constraint, the cascade |
| `docs/PROJECT-NOTES.md` | Running engineering notes |
| `docs/POSE-PROBE.md` | Pose probe findings |
| `docs/SESSION-LOG.md` | One entry per session — see the ritual below |

**In the assets workspace — business, legal, and session memory, never committed:**

`MEMORY.md` · `working_arrangement.md` · `user_role.md` · `feedback_session_ritual.md` ·
`feedback_dugout_git_discipline.md` · `reference_connector_profiles_dugout.md` ·
`dugout_*.md` (product model, competitive, MVP, app store plan, jira state, tip library,
unit economics, user workflows, legal minors) · `Strategy & Business/` · `Product & Specs/`

A Claude Code session that needs product or business context reads those by **absolute path**
from the assets workspace. It will not find them by walking up from the repo.

**Rule:** a document has exactly one original. If it is about how the code works, the original
is in `docs/` here. If it is about the business, the original is in the assets workspace. The
DugOut Claude project holds published mirrors for reading on a phone — never edit a mirror.

---

## Architecture invariants — do not break these

1. **No build step.** GitHub Pages serves the repo as-is. There is no bundler, no transpile,
   no `npm run build`. Scripts are plain `<script src>` tags in dependency order.
2. **Offline-first: zero external network references.** No CDNs, no Google Fonts, no remote
   models. Fonts are self-hosted woff2 in `css/fonts/`; TF.js and the MoveNet model are
   vendored in `vendor/`. If you add a reference to a URL, you have broken the iOS wrapper
   and the offline demo. This is checkable — grep the entry point for `http`.
3. **All AI calls go through the single adapter in `js/ai.js`.** With no key configured the
   app must still segment, evaluate, and render from a deterministic stub. The static demo
   is what gets shown to trainers; it has to feel real.
4. **Persistence is local** — localStorage plus IndexedDB for clips. Every stored object
   carries `profileId` so accounts can bolt on later. Auth tokens, when they exist, live in
   the iOS Keychain via the bridge — **never `localStorage`**.
5. **Raw session video is deleted after segmentation.** Only swing clips or ranges persist.
6. **The six checkpoints — Stance, Load, Stride, Hips Fire, Contact, Finish — are the spine**
   of the session rubric, the tip library index, and the philosophy structure. Internal
   scores are never displayed; the user sees PASS/FAIL only, and scores never cross an API
   boundary.
7. **The app never ships an API key.** Any hosted-model key lives only in a server-side proxy.
8. **A coach never has access to raw video.** Results only — pass/fail marks, priority focus,
   the swing reel.

## Xcode wrapper (`ios/`)

Resources are **folder references**: `index.html`, `css`, `js`, `vendor`, plus
`shadow-sprite.jpg` and `swing-shadow.mp4`. All relative, all inside this repo.

- New files under `css/`, `js/`, or `vendor/` ship automatically — no project change.
- A new **top-level** file or folder needs a `project.pbxproj` edit or it won't be bundled.
- The wrapper runs a loopback HTTP server on 127.0.0.1 so `localhost` is a secure context —
  that is what makes `getUserMedia`, the local model fetch, video byte-range scrubbing, and
  IndexedDB work. `file://` breaks the first two. Don't "simplify" this away.
- Every change needs a rebuild in Xcode. Remind Derell.

## Build scripts

- `scripts/build_library.py` — the **only** thing that may write `js/library.js`. Converts
  the tip-library spreadsheet from the assets workspace. Resolves the sheet via
  `$DUGOUT_ASSETS` → repo sibling → the known OneDrive path, and errors with every path it
  tried. Never hand-edit `library.js`.
- `scripts/build_index.py` — historical one-shot assembler. Needs a `main_inner.html`
  fragment in `$DUGOUT_SCRATCH` or `scripts/_scratch/`. Not part of the normal loop.

---

## Verification — required before any delivery

Do not report work as done on the strength of having written it.

1. **Serve the repo and boot headless at iPhone viewport with all external network blocked.**
   Report console errors, page errors, and failed requests. The number is zero, or you
   explain every one.
2. **Cross-check every asset reference** in `index.html` against files that exist.
3. **Confirm external network references still number zero.**
4. **Segmentation changes must be verified against the real clips** in the assets workspace
   at `Design & UX/media/test-clips/` — `Three Swings.mov` (3 real swings, contacts at
   ~4.3 / 31.6 / 57.3s by audio ground truth) and `pitch_01.mov` (2) are the regression pair.
   Run it more than once; this pipeline has produced flaky results before.
   **Headless Chromium has no H.264/AAC** — remux test clips to VP9/Opus webm first. The
   device runs the originals.
5. **Scan for SharePoint metadata injection** before committing — `xmlns:mso`,
   `CustomDocumentProperties`, or a blanked `<title>`. It has happened here before.

---

## Git

**One-time fix, run once per clone:**

```
git config core.fileMode false
```

Without it the Cowork bridge mounts every file `0755` and git reports the entire tree as
modified, burying real changes. With it, `git status` tells the truth from either surface.

**Never run git through the Cowork device bridge.** Reads are fine; anything that writes —
commit, push, merge, rebase, checkout — gets handed to Derell as a copy-paste Terminal block
with real absolute paths and no placeholders. His terminal comfort is copy-paste level:
exact commands, no gaps to fill in.

**The bridge cannot delete files.** `rm` fails with "Operation not permitted." To remove
something, `mv` it into a `_to_delete/` folder and say what you moved and where.

**Uncommitted work is a blocker, not a footnote.** If real changes are unpushed, say so
before starting new work and quantify it — how many files, how many lines, which features.
Branch per ticket, Jira key in the branch name and in the commit subject. Commit at the end
of each session; push the same day.

### Never commit

Video and raw footage · the tip-library spreadsheet (it is the human-edited source of truth
in the assets workspace) · API keys, tokens, `.env` files, `.p8` files, signing certs ·
`node_modules/` · `__pycache__/` · `.DS_Store`. A committed key is a **compromised** key —
rotate it, don't just delete it.

### Never logged — any level, any environment

Clip bytes or frames · pose keypoints · a child's name · internal checkpoint scores · auth
tokens · Apple identity tokens. Logs reference the opaque `profileId` only.

---

## Session ritual

**Open:** read this file, then `docs/SESSION-LOG.md`. Check `git status` and state the
working-tree condition before proposing work.

**Close:** append one entry to `docs/SESSION-LOG.md` —

```
## YYYY-MM-DD — <what this session was about>
Tickets: DUG-xx
Changed: <files / what landed>
State: <committed+pushed | branch open | uncommitted>
Next: <the one thing the next session should pick up>
```

Then commit. A session that ends without a log entry and a commit did not happen.

---

## Working with Derell

- He builds and tests on a real iPhone via Xcode Run. Rebuild required for every change.
- Write files directly into the repo. Never hand him zips.
- Atlassian/Jira MCP calls must be **sequential** — parallel calls fail with
  "permission stream closed."
- Staging carries synthetic athlete data only — never a real child's session, in any
  environment, for any reason. Production credentials never touch a laptop.
- No third-party SDKs in the app.
