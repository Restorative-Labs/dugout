# DugOut — Canon

**The ruling ledger. One home for every decision that is a number or a rule.**

Compiled 2026-09-04, the day the CPO role was established. Seeded from `CLAUDE.md`, the
System TDD, the Segmentation TDD, the COPPA memo, the MVP definition, and the code itself.

## How to use this file

- **`js/config.js` is authoritative.** Where this file and that file disagree, the code wins
  and **this file is the bug**. Fix it here, then say so in the session log.
- **Never write a number into prose that is not also in `config.js`.** This is a ledger of
  rulings, not a second configuration. A prose number and a config number that can disagree
  will eventually disagree — see R-14 for what that costs.
- A fact is **publishable** only when `RULED && enforced`. Ruled by Derell is not enough; if
  nothing in the code or a signed document enforces it, it is not publishable and must not
  appear in a mockup, a deck, the App Store listing, or anything a customer sees.
- **Status vocabulary:** `RULED` (decided and enforced) · `PENDING` (open, awaiting a
  decision) · `PROVISIONAL` (in use, not yet validated against evidence) · `CONTRADICTED`
  (code and prose disagree; the discrepancy is the work).

---

## Product invariants — RULED, enforced in code and review

| # | Ruling | Source | Enforced by |
|---|---|---|---|
| R-01 | The six checkpoints — Stance, Load, Stride, Hips Fire, Contact, Finish — are the spine of the rubric, the tip-library index, and the philosophy structure. | Product model | `config.js PHASE_WINDOWS`, `evaluate.js` |
| R-02 | **Internal checkpoint scores are never displayed.** The user sees PASS/FAIL only — not in a tooltip, not in a debug panel a user can reach, not anywhere. Scores never cross an API boundary. | Product model | Review; `.claude/rules/checkpoints.md` |
| R-03 | **A coach never has access to raw video.** Results only — pass/fail marks, the priority focus, the swing reel. | User workflows, visibility matrix | Review; `.claude/rules/visibility.md` |
| R-04 | **Raw session video is deleted at segmentation.** Only swing clips or ranges persist. It never leaves the device. | Product model, COPPA memo | `segment.js`, `store.js` |
| R-05 | Coach philosophy is **selection, never authoring.** A coach picks tips, orders them, bans cues, and maps his own slang onto library tips. He cannot invent a fault or remove a safety rail. | Product model | Review; `.claude/rules/visibility.md` |
| R-06 | The tip library is **closed and human-vetted.** The app never invents a fault, a cue, or a drill. `scripts/build_library.py` is the only thing that may write `js/library.js`. | DUG-37 | `build_library.py`; review |
| R-07 | **Offline-first: zero external network references.** No CDNs, no Google Fonts, no remote models. Checkable — grep the entry point for `http`. | CLAUDE.md invariant #2 | Headless verification gate; `scripts/ship_checks.py` in the TestFlight lane (R-45) |
| R-08 | **No build step.** GitHub Pages serves the repo as-is. | CLAUDE.md invariant #1 | Structural |
| R-09 | **The app never ships an API key.** Any hosted-model key lives only in a server-side proxy. | Security posture | Review; never-commit list |
| R-10 | Auth tokens live in the **iOS Keychain** via the bridge, never `localStorage`. | DUG-73 | `.claude/rules/privacy.md` |
| R-11 | **No third-party SDKs in the app.** (Apitor was fined Sept 2025 for a vendor SDK's behavior.) | COPPA memo | Review |
| R-12 | **Staging carries synthetic athlete data only** — never a real child's session, in any environment, for any reason. Production credentials never touch a laptop. | Security posture | `.claude/rules/privacy.md` |
| R-13 | **Never logged, any level, any environment:** clip bytes or frames, pose keypoints, a child's name, internal checkpoint scores, auth tokens, Apple identity tokens. Logs reference the opaque `profileId` only. | DUG-128 | `.claude/rules/privacy.md` |
| R-45 | **Builds reach testers only through `cd ios && fastlane beta`, and only as a commit.** The build fails on: an outside address in the app's entry point — the Swift it compiles, its Info.plist, the URL strings in its executable, `index.html` — or in a stylesheet, our own `js/` (the AI adapter's endpoint is the one allowed address, invariant 3) or the pose model's location; SharePoint marks (xmlns:mso, CustomDocumentProperties, a blank head `<title>`); debug on (`DEBUG` must be `false` — DUG-153, added 2026-10-20 after build 4 shipped with it on); anything in the app that is not the commit's web files, untouched (no transforms, no over-the-air updates), including credential-like files or pasted keys; a wrong bundle id, build number, or `ITSAppUsesNonExemptEncryption` other than NO. Dry runs never write to Apple. | DUG-63 brief (Derell, 2026-10-20); DUG-96, DUG-97, DUG-44 | `scripts/ship_checks.py`, run by `ios/fastlane/Fastfile` before the archive and again on the `.ipa`; 79 planted cases in `scripts/test_ship_checks.py`. First run: build 1.0 (4), 2026-10-20 |

---

## Open and contradicted — the work

| # | Item | Status | Why it matters |
|---|---|---|---|
| R-14 | ~~`SPIKE_ENTER_MULT: 3.0`~~ → **2.4 as of `3b7fae6` (2026-09-08).** Diagnosis resolved and shipped; the wrong "3-8x" comment is corrected in the file. **The value itself is still proxy-measured** — the four stable runs cited in the commit are headless, and headless requires a VP9 remux while motion energy *is* inter-frame delta. **Status: diagnosis RESOLVED, value PROVISIONAL** pending a device run on original H.264 across all five `pitch_0*.mov`. Original entry follows. `SPIKE_ENTER_MULT: 3.0`. The comment beside `MAX_SPIKE_MULT` asserts *"real swings measured 3-8x"*; the 2026-09-04 regression measured a maximum real swing of **2.98×** on both ground-truth clips, and both returned **zero swings**. Prose and config disagree. | **CONTRADICTED** | This is the canonical example of why this file exists. A threshold with zero headroom is a defect whichever side today's footage lands on. **The proposed 2.4 is proxy-measured** (headless requires a VP9 remux; motion energy *is* inter-frame delta, so the codec moves the number) and is not ruled. Needs device measurement on original H.264 across all five `pitch_0*.mov` clips. |
| R-15 | `CONTACT_ANCHOR: 0.62` is the designed contact position within the swing window. `segment.js` does not honour it — measured 0.500 / 0.761 / 0.572 depending on audio confirmation. | **CONTRADICTED** (DUG-54) | The error flips direction depending on whether audio confirmed the swing, so a whiff and a solid contact in one session are oppositely mis-registered. Silent — six plausible marks still render. |
| R-16 | Launch pricing. The screen-flow mockup renders **"Player · $99/yr"** and a renewal date. **Nothing has ruled this.** | **PENDING** (DUG-25) | Under the publishable test this number is `RULED=false` → not publishable. It must not appear in the App Store listing, a deck, or anything a parent sees until DUG-25 is ruled. The mockup is internal only. |
| R-17 | Backend stack. | **PENDING** (DUG-66) | Input to the release ladder, not independent of it. |
| R-18 | Media storage — R2 vs S3, and the sync default. | **PENDING** (DUG-70) | Interacts with R-04: whatever is chosen must not create a second copy of raw video. |
| R-19 | Coach roles and philosophy scope. | **PENDING** (DUG-36) | R-05 bounds it; the open question is how far selection extends. |
| R-20 | COPPA compliance checklist. | **PENDING** (DUG-13) | The 2025 amendments compliance date (2026-04-22) has **passed**. "Gait patterns" is now a biometric identifier — directly relevant to pose keypoints. |
| R-37 | **The checkpoint taxonomy is hardcoded, and pitching needs a different one.** R-01 makes Stance / Load / Stride / Hips Fire / Contact / Finish the spine of the rubric, the tip-library index **and** the philosophy structure simultaneously — three systems keyed to six hitting-specific names. | **OPEN — surfaced 2026-09-12** | "Add pitching" is therefore not a feature but a schema change across three systems, and probably not six checkpoints. The 16 Jul brief anticipated "same chassis, new taxonomy," but nothing in the design makes the taxonomy a parameter rather than a constant. **Cheapest to address now**, while the tip library is seed v0.2, rather than after a trainer has vetted a corpus keyed to hitting. Does not block the October launch; does bound how the tip library should be structured before DUG-37 review. |
| R-38 | **EU Digital Services Act trader status is a submission gate.** App Store Connect banner, seen 2026-09-13: *"Developers must provide their trader status to submit new apps for distribution in the European Union… your apps will be removed from the App Store in the EU."* | **OPEN — surfaced 2026-09-13** | Not in the COPPA memo, the System TDD or the release ladder. Two paths: declare trader status (requires a verified business address and contact details published on the listing), or **exclude the EU from availability at launch** — which costs nothing in 2026 since the GTM is US youth baseball. Recommend excluding the EU for v1 and revisiting only if there is real EU demand. Decide before the App Store Connect availability step, not at submission. |
| R-39 | **The spec contradicts itself on what a coach can see — and it is the most legally load-bearing grant in the product.** W1.5's approval copy says the coach sees *"pass/fail marks, the priority focus, and the swing reel."* W3.4 says his view is *"exactly what the parent sees. No raw footage."* The visibility matrix says **Swing clips — Coach: NO.** And the consent screen promises the parent *"a coach you approve sees pass/fail marks — never your video."* | **OPEN — owner Derell, surfaced 2026-09-14** | "Swing reel" is overloaded: on the Round Card it is a grid of **clips you tap to scrub**. The design canvas draws the **stricter** reading — per-swing marks, no clips — because that is the only reading consistent with R-03, R-04 and the consent copy. A ruling is needed either way, and the looser reading would require **rewriting the consent screen**, not just the coach-approval screen. Found by review of the design canvas, 2026-09-14. |
| R-46 | **The privacy policy ships as a page inside the app** — not a link out to the web. A privacy policy link is expected before App Store submission (DUG-15 / DUG-107 draft the policy; App Store Connect itself still needs a public policy URL, which the website may host); an outside link such as `<a href="https://restorative-labs.github.io/dugout/privacy.html">` in `index.html` would fail the build under R-45. | **RULED — Derell, 2026-10-20** (DUG-63). Enforced by R-45: an outside link fails the build. | Keeps R-07 and R-45 unchanged; the policy works offline and cannot drift from the build that showed it. **To build it:** a new top-level page (e.g. `privacy.html`) needs a `project.pbxproj` edit *and* an entry in `SHIPPED` in `scripts/ship_checks.py` — the checks refuse the build until both agree. The website may also publish the same text; the app never links to it. |
| R-21 | `AUDIO_CONFIRM_SEC: 0.75`. Two measurements in `config.js` disagree on the peak→ping offset: 0.5–0.7s (backyard) vs 1.03s (`pitch_01`). Neither checked against more than one clip. | **PROVISIONAL** | If 1.03s is representative of cage footage, the window excludes the real ping and every swing is treated as a whiff. |

---

## Rulings that changed the plan

| # | Ruling | Date | Consequence |
|---|---|---|---|
| R-22 | **StoreKit 2 requires no backend.** Payments were bundled with cloud accounts because both were labelled R3; they are separable. | 2026-09-01 | Moved first revenue from February to October. Payments no longer wait on identity. |
| R-23 | **Derell is the sole operator.** No reviewer, no assignee, no second name on any ticket, document or process. | 2026-09-01 | Nine ticket descriptions swept. Any process step requiring a second person is a design error. |
| R-24 | **Sell in 2026.** Dads and teams this year; teams already on it by spring. | 2026-09-01 | The board's dates still reflect the superseded pilot-Nov-2 plan. Reconciling them is open work. |
| R-25 | **A model can only confirm a candidate, never find one.** Hosted models sample video at a hard 1 FPS; a swing is 130–280ms. Frames extracted and sent as *images* bypass the ceiling. | 2026-09-01 | Detection stays deterministic and on-device permanently. This is architecture, not a current limitation. |

---

## CPO rulings — 2026-09-04

Ruled under the charter in `CLAUDE.md`. Each is **RULED**; none is **publishable** until the
enforcement column is true. Derell may override any of these — that is what "ruled, not
final" means.

### R-26 · Launch pricing — DUG-25 · RULED, not yet publishable

**Player $99/yr, or $14.99/mo. One tier at launch. No free tier.**

The annual is the gift-season SKU and the monthly is the in-season SKU; the monthly annualises
to $180, which prices the annual as a 45% saving without a discount ever being advertised.

*Reasoning:* the comparison a parent actually makes is not other apps — it is **a lesson**. One
private hitting lesson runs $60–100. A year of DugOut priced below a single lesson makes the
decision trivial, and that framing survives contact with a dad in a cage in a way that a
feature comparison does not. Every credible competitor is hardware-anchored ($150+ of sensor
before any subscription); software-only on a phone he already owns is the wedge, and pricing
near hardware would forfeit it.

*Enforced by:* nothing yet. **Not publishable** — must not appear in the App Store listing, a
deck, or any parent-facing surface until the StoreKit products exist and charge these amounts.
This supersedes the `$99 / yr` currently rendered in the screen-flow mockup (R-16), which
remains internal-only.

*What would change this:* evidence that youth-sports parents anchor on app pricing rather than
lesson pricing; or a coach-tier design where the player tier is better used as an on-ramp.

### R-27 · Backend stack — DUG-66 · RULED

**No backend before November. When built: one Next.js app, one Postgres, no Clerk.**

Nothing that ships before November needs a server. StoreKit carries identity, entitlement and
renewal (R-22); the app is local-first (R-04). The first genuine server requirement is the
coach roster and dashboard in the Nov–Dec window.

**No Clerk.** Sign in with Apple is already the ruled v1 identity, native in the Swift shell.
Clerk would add a third-party vendor holding children's identity in exchange for features we
have ruled out — and it collides with R-11.

*Reasoning:* this ruling removes work from the critical path rather than adding it. At the
scale this business reaches by March — hundreds of families, dozens of coaches — one app and
one Postgres is not the constraint; a second moving part is an operational tax paid by one
person.

*What would change this:* a coach-facing requirement before November that genuinely cannot be
served from the device.

### R-28 · Media storage and sync — DUG-70 · RULED (deferral) + RULED (default)

**Sync is OFF by default. R2-vs-S3 is deferred to November — deliberately undecided.**

*Reasoning:* deciding the object store in September means deciding it with less information
for no benefit, since nothing writes to it before November. What *is* decidable now is the
default, and it must be off: a sync feature that quietly uploads a child's session inverts the
promise the product is sold on.

**Binding constraint on whatever is chosen:** no storage or sync feature may create a second
copy of raw session video. R-04 is not negotiable by a storage decision. Only swing clips or
ranges may ever be candidates for sync, and only with explicit per-athlete consent.

### R-29 · Coach philosophy scope — DUG-36 · RULED

**Philosophy v1 is exactly four verbs: pick, order, ban, rename.**

A coach may select tips from the library, set their priority order, ban specific cues, and map
his own slang onto existing library tips. Nothing else. No custom tips, no custom faults, no
per-athlete overrides, no free-text coaching notes in the graded path.

*Reasoning:* R-05 already forbids authoring. This ruling draws the line at the exact place
where selection stops being selection. Every extension multiplies the vetting burden on a
closed, human-vetted corpus — and that corpus is the moat, not the feature list. "Rename" is
included because it is what makes a coach feel heard at zero corpus cost: his words, our
vetted content.

### R-30 · COPPA posture — DUG-13 · RULED

**Drop the self-serve 13–17 tier. Every account is created by an adult.**

*Reasoning:* it is not built, so dropping it costs nothing today and removes an entire
regulatory surface — a self-serve minor tier means minors contracting without a parent, and
it is the single largest source of avoidable exposure in the current design.

**Pose keypoints are biometric.** The 2025 amendments enumerate "gait patterns" as a biometric
identifier; pose keypoints are exactly that. They never leave the device, are never logged at
any level (R-13), and the privacy policy must say so explicitly rather than by implication.

*Still open under this ruling:* the written retention policy required by §312.10 must be
published in the notice, and §312.8 requires a written security program plus written vendor
assurances. Both are drafting work, now unblocked — **DUG-126** and the privacy policy.

---

## CPO rulings — App Store launch · 2026-09-08

Source: the App Store Launch Handoff (browser-only work on Derell's signed-in Apple session,
8 Sep 2026). Apple Developer team `NKNR8F3VKC` (Restorative Labs LLC, Organization, renews
2027-08-19). A free personal team `KX2L3Q37G7` on the same Apple ID holds the original DugOut
build and is the root of both blockers.

### R-31 · Bundle ID — RULED: register a new one now, do not wait for Apple

`com.restorativelabs.dugout` is stranded on the personal team and invisible from the
Organization portal. Support case **102956802933** asks Apple to release it. **That case is a
cleanup item, not a gate.**

**Register `com.restorativelabs.dugout-ios` under `NKNR8F3VKC` today** and create the App Store
Connect record against it.

*Reasoning:* a bundle ID is invisible to users — it appears in no store listing, no home
screen, no receipt. Nothing is on TestFlight yet, so there are zero builds to orphan and
nothing keyed to the old ID (no Sign in with Apple config, no App Groups, no Keychain sharing
exists). The migration cost is therefore **zero**, while the support case has **no SLA** and
October submission is the target. Waiting an unknown number of weeks on a string no user ever
sees, to protect the critical path's most valuable asset — time — is the wrong trade.

*Keep the case open.* If Apple releases the identifier later, it costs nothing to hold.

**2026-09-09 — the case escalated, confirming this ruling.** Apple Developer Support (Vagan)
replied: *"I have routed your case to our senior support team for further review and
processing. Please be on the lookout for an email from a senior advisor."* No turnaround
estimate, second time of asking. Tier 1 could not action a cross-team identifier release, which
is consistent with it being a manual account operation rather than a self-serve one. Two data
points now say indefinite; none says short. **Proceed on the new identifier today.** Do not
reply to the case — a reply saying we have moved on invites closure — but do answer a senior
advisor if one writes, since the identifier is still worth recovering for free.

### R-32 · Store listing title — ~~RULED: Dugout: Film Room~~ **SUPERSEDED 2026-09-10 by R-35**

Subtitle carries the keywords and the promise; the title carries the distinctness.

*Reasoning:* "Dugout" is a **commodity noun** in youth baseball software, not an asset. Live
today: Dugout App, Dugout Genius, Dugout Analytics, DugoutIQ, Prospect Dugout, Dugout 360,
Dugout Dude. Being the eighth "Dugout" — and the last to market — means every word-of-mouth
mention leaks to someone else. Our GTM is cages, teams and Mike White, not App Store browse,
so **distinctness beats keyword legibility**, and Apple indexes the subtitle for search anyway.
"Film room" is what a coach actually says, and it names a surface the app already has
(`filmroom.js`, `filmshell.js`, Film Space v2).

*The objection, stated:* "Film Room" implies the user watches video and works it out — the
opposite of the promise, which is *one thing to fix, after every round*. The subtitle must
carry that, or the title undersells. **This is the ruling most worth Derell overriding**, and
it is cheap to change — App Store titles update with any new version.

*Alternatives cleared and rejected:* Dugout Swing, Dugout Hitting (most legible to a parent,
least distinct — sits directly beside the existing field), Dugout Reps, Dugout Academy.

### R-33 · Home-screen name — RULED: stays **DugOut**

The store listing title and the home-screen app name are separate fields. Whatever the listing
says, the icon on the phone says DugOut. The wordmark, the design system and the `DUG` Jira key
are unaffected by R-32.

### R-34 · No trademark filing — RULED (Derell, standing)

No trademark claim has been filed and none will be, unless Derell says otherwise. This is
recorded so no future session proposes it as a solution to R-32.

---

## R-35 · Store listing title — ~~RULED: Dugout Hitting~~ **SUPERSEDED 2026-09-12 by R-36**

**Supersedes R-32.** Fallback if App Store Connect rejects it: **Dugout Reps**.

### Why R-32 was withdrawn

**"Film Room" is GameChanger's.** DICK'S Sporting Goods launched *Film Room* in October 2024
as GameChanger's AI-powered video analysis tool, built on AutoStream. GameChanger has **6M+
unique users at ~45 minutes/day**, 11% YoY growth, and its founding franchise is youth
baseball and softball — Film Room is on basketball and volleyball today, so baseball is a
question of timing, not direction.

Naming DugOut after a feature of the category's dominant app would subordinate the brand to
theirs, leak every "film room" search in youth sports to them, and worsen over time. R-32
reasoned correctly that DugOut must not become a modifier on someone else's brand, then chose
a name that did exactly that. **The error was not checking the market leader before ruling** —
and GameChanger's Film Room was already documented in `competitive-landscape.md` (16 Jul 2026),
so the check required reading a project doc, not new research.

*Internal note:* the repo calls the feature "Film Space" (`filmroom.js`, `filmshell.js`,
"Film Space v2"). Internal naming is unaffected, but no customer-facing copy should use
"film room" as a product noun.

### The new ruling

**Title: `Dugout Hitting`.** Subtitle carries the promise — *one thing to fix, every round*.

*Reasoning, corrected:* R-32 over-weighted App Store distinctiveness. Discovery here is
word-of-mouth — cages, teams, Mike White — and the brand people say is **DugOut**, which the
home screen carries regardless (R-33). The listing title's job is therefore narrow: lead with
the brand so someone told "get DugOut" finds it, add the category word so the searches that do
happen land, and collide with nobody. Cleverness bought nothing and cost a great deal.

"Hitting" is the category word and is uncrowded — "Swing" collides with Dugout AI, WIN Reality
SwingAI and V1 Swing Analyzer.

*Namespace as of 2026-09-10* — at least twelve live "Dugout" apps: Dugout App, Dugout Genius,
Dugout Analytics, DugoutIQ, Prospect Dugout, Dugout 360, Dugout Dude, Dugout Scoreboard, BBFS
Dugout, Dugout C-Stores, The Dugout TDO, Dugout – Scores Fans & Banter. Neither `Dugout
Hitting` nor `Dugout Reps` returns an exact match.

*Confidence:* search-engine clearance, not first-party. **App Store Connect is the arbiter** —
it hard-rejects a taken name at save, so this resolves in seconds at record creation.

---

## R-36 · Store listing title — **RULED AND ENFORCED** 2026-09-13: **Dugout: Next Rep**

**Supersedes R-35 (`Dugout Hitting`), which superseded R-32 (`Dugout: Film Room`).**

| Field | Value | Chars |
|---|---|---|
| App name | `Dugout: Next Rep` | 16 / 30 |
| Subtitle | `Hitting: one fix every round` | 28 / 30 |
| Home screen | `DugOut` (R-33, unchanged) | — |

### Why

Derell's framing settled it: **the app is designed on feedback loops.** "Next Rep" *is* the
loop, stated as an action rather than a noun — and it is what a coach says out loud. No
competitor's name does that.

It is also **forward-looking rather than diagnostic**, which matters more here than it sounds.
"Checkpoints" tells an eleven-year-old he is being graded. "Next Rep" tells him what to do.
For a product whose governing rule is *one thing to fix, never a score* (R-02), the name
carries the positioning instead of fighting it. It quietly implies the session model too —
reps, plural, inside a round.

"Feedback" itself was rejected as the descriptor: it is the vocabulary of measurement, and
measurement is what DugOut differentiates against. Per the July brief, *"gadgets are not
hitting coaches."*

### Clearance — run BEFORE ruling this time

- **Market leaders: clear.** GameChanger, WIN Reality and Blast Motion use "next rep" nowhere.
  WIN's language is "the one cue" and "WIN Hitting System." This is the check R-32 skipped.
- **Exact App Store name: clear.** No `Dugout: Next Rep` or `Dugout Next Rep` listing.
- **Accepted caveat — "NextRep" is crowded in fitness:** four live iOS apps (NextRep; NextRep:
  AI Workout Planner; NextRep Challenge; NextRep AI), two on Google Play, plus nextrep.app.
  All gym/workout. Apple's uniqueness rule applies to the **full string**, so registration
  should pass; and since discovery is word-of-mouth, a parent searches *dugout*, not *next rep*.
  The `Dugout:` prefix sets the baseball frame before the reader reaches the second word.
  **This is a different risk class from R-32** — small apps in an adjacent category, not the
  category king owning the exact phrase.
- - **First-party confirmed 2026-09-13.** App Store Connect **accepted the name at record
  creation** — it hard-rejects a taken name at save, so `Dugout: Next Rep` is now held by
  Restorative Labs LLC. The record shows *iOS 1.0 Prepare for Submission*. Fallbacks
  (`Dugout: Swing Check`, `Dugout: Cage Work`) are no longer needed.

**This ruling is now `RULED && enforced` — publishable.** R-16's block on customer-facing
naming is lifted for the title. Pricing (R-26) remains **not** publishable until StoreKit
charges it.

### Rejected in this round, with reasons worth keeping

`Cue` — WIN Reality markets "the one cue" at DugOut's exact price. Theirs in this category.
`Lab` — PitchLab is a live competitor at 4.8★ / 1.3K ratings.
`AI` / `SwingAI` — WIN owns SwingAI; and per the July brief, raw-LLM coaching has a documented
hallucination problem, so "AI" in the name invites the objection rather than answering it.
`Vision` / `Eye` — SwingVision exists; Coach's Eye is the legacy everyone knows.
`Film` — GameChanger's.
`Academy` — promises a curriculum that does not ship.
`Coach` — fights the positioning: DugOut amplifies the coach, it does not replace him.

### The subtitle is the scope field — RULED 2026-09-12

Asked whether the subtitle should say "Hitting" given that pitching is on the roadmap: **yes,
keep it.**

The app record **name** changes only with a version submission and accrues the brand; the
**subtitle** is expected to change and is rewritten freely at any release. So the title stays
scope-neutral and the subtitle carries current scope.

`Next Rep` **is already scope-neutral** — a pitcher throws reps. This was not the reason it was
chosen, but it means the title survives the pitching expansion where `Dugout: Checkpoints` or
`Dugout Hitting` would not have.

Specificity therefore costs nothing and buys conversion: a parent browsing for hitting help
converts on "Hitting: one fix every round" and not on "Baseball Training." A subtitle implying
pitching before pitching ships earns accurate one-star reviews and risks a misleading-metadata
rejection. Pitching is not on the ladder through spring 2027 — the 16 Jul brief has it as
"post-beta, open question."

**Confirmed by Derell 2026-09-13.** Rejected in the same pass: `Hitting: Corrective Feedback
Each Session` — 41 chars (over Apple's 30-char subtitle limit, verified against App Store Connect
documentation), and "corrective" carries a remedial edge that fights R-02 while "feedback" is the
commodity word the title was chosen to avoid.

**Triggers to revisit — change the subtitle, never the title:**

1. **The Nov–Dec coach release.** The audience shifts from parent to coach, and benefit copy
   stops being the strongest pitch. `Hitting: 6 checkpoints, 1 fix` (29) is the noted candidate:
   it signals the closed rubric no competitor has and pre-empts the "is this a toy?" objection a
   trainer brings. Not ruled — flagged so the coach release does not ship parent copy by default.
2. **The first release shipping any pitching analysis.** Drop "Hitting." Do **not** add
   "pitching" to the subtitle or keyword field before the feature is live — Apple rejects
   metadata for features that are not present.

### Apple state as of 2026-09-13

| Item | Status |
|---|---|
| App ID | **Registered** — `com.restorativelabs.dugout-ios`, description `DugOut`, team `NKNR8F3VKC`, Explicit, **Sign In with Apple enabled** (only capability) |
| App Store Connect record | **Created** — `Dugout: Next Rep`, iOS, en-US, SKU `DUGOUT-IOS-001`, Full Access. Status *1.0 Prepare for Submission* |
| Support case 102956802933 | Still open, now irrelevant to the critical path. Answer a senior advisor if one writes; the old identifier is worth recovering for free but blocks nothing |
| Apple flagged at registration | Sign in with Apple needs Private Email Relay domain + email-source registration before it works — **DUG-123**, already on the board |

### Unaffected by this ruling

Bundle ID `com.restorativelabs.dugout-ios` (R-31) — chosen to be name-independent on purpose.
Home-screen name `DugOut` (R-33). No trademark filing (R-34).

---

## Competitive correction — 2026-09-08

The handoff described **"Dugout App"** (Nathan Simon / The Dugout Inc) as *"a real functional
competitor... already ships AI swing analysis."* Verified against the live listing — **downgrade
that read.**

Its subtitle is **"Team Management for Everyone."** It positions against GameChanger and
TeamSnap, and "Video Analysis: instant AI feedback" is one bullet among roughly twenty, filed
under *For Players* between **Digital Trading Cards** and **Walkup Songs**. IAP runs to
$699.99 — org-level pricing. The CA storefront shows v1.1.6 (21 May) and *"hasn't received
enough ratings to display an overview."*

**It is a name collision with a feature overlap, not a competitor.** Swing analysis is a
checkbox in a roster app.

**The actual competitive set** — dedicated swing products, none of them named Dugout — is
**WIN Reality (SwingAI)**, **V1**, **b4-app: AI Batting Partner**, and **Athletech Baseball AI**.

> **Correction, 2026-09-10.** This section originally claimed those products "were not in
> `competitive-landscape.md` and belong there." **That was false.** All four are documented in
> the 16 Jul 2026 brief, in detail — WIN SwingAI is named there as the top threat at DugOut's
> identical price point. GameChanger's Film Room is in it twice, including an explicit
> instruction to *"watch Film Room expanding to baseball/softball."*
>
> What my 8–10 Sep searches actually added was only the **name-collision** list (a dozen live
> "Dugout" apps) and **"Dugout App"** by Nathan Simon. Everything else was already known.
>
> **This is the same failure as R-32: ruling before reading what the project already knew.**
> The `premise` skill exists for exactly this and was not run. Before any competitive or
> positioning ruling, `project_read` the competitive brief first — it is more thorough than a
> live search will be, and staleness is a separate question from absence.

*What this changes:* the name problem is **worse** than the handoff framed it (seven Dugouts,
not one) and the product problem is **better** (no one has shipped the closed-corpus,
one-fix-per-round approach). Both point the same way — differentiate on the name, not the
noun.

---

## Amending this file

A new ruling is appended with its number, its source, its date, and its status. A ruling is
never silently edited — if it changes, the old row is marked superseded and the new row cites
it. `CONTRADICTED` rows are closed by fixing the code or the comment, never by deleting the row.
