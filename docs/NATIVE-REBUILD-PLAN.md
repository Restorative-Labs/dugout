# DugOut — native rebuild: the ruling, the sizing, and the order

**Date:** 2026-10-14 · **Ruled by Derell:** DugOut is rebuilt as a native iOS app in Swift.
**Status:** architecture ruling recorded. No code written. No Jira changes.
**Canonical copy:** `docs/NATIVE-REBUILD-PLAN.md` in the repo. The copy in the
Claude project is for reading away from the Mac. Per `CLAUDE.md`, a document
about how the code works keeps its original in `docs/` — this one lived only in
the project until 2026-10-20, which is why three files cited a §5.1 that no
session could open.
**Sized against the actual repo** at `/Users/derelljenkins/code/dugout` (branch `DUG-40-film-controls`, `643c364`), not estimated.

---

## 1. The ruling

**RULED (Derell, 2026-10-14):**
1. **DugOut is a native iOS app.** Swift, not HTML/JS in a WKWebView.
2. **Capture is native.** No `getUserMedia`, no webview camera.
3. **The website is marketing, information and login only.** It is no longer the product.
4. **The rebuild incorporates the evidence-driven screen changes** made today (`ux-evidence-base.md` §7, §2, §10).
5. **February 14 is explicitly set aside** as a constraint on this decision. Derell: *"don't worry about the date, only about what's the right thing to do."* It returns as a planning input once the rebuild is sized into sprints.

**Supersedes:** R-07 (*no build step*). That rule governed the web bundle and is now false — a native app has a build step by definition. **R-07 should be retired in CANON, not quietly ignored.**

**Also now stale:** the Oct 14 S02 plan in `claude/s01-review-and-s02-plan-2026-10-14.md` re-slots tickets for the webview product. **Do not give it the go.** It would spend ~30 minutes of Jira edits filling the board with work for an architecture that no longer exists.

---

## 2. The sizing — 5,717 lines of JS, and only ~1,150 of it is hard to replace

| Fate | Files | Lines | Notes |
|---|---|---|---|
| **A · Deleted — architectural tax** | `shell.js` 611, `filmshell.js` 320, `pose.js` 112, `ios/LocalHTTPServer.swift` | **1,043** | Plus **5.7 MB** of `vendor/` — TensorFlow.js (1.09 MB) and the MoveNet model (4.7 MB). All of it exists to make a browser do what the OS does natively. |
| **B · Ports as data, not code** | `library.js` | **1,478** | The Tip Library. Content, not logic — becomes a bundled JSON resource. Near-zero porting risk, and it is already on the Edit deny list. |
| **C · The real port — irreplaceable logic** | `segment.js` 548, `evaluate.js` 459, `config.js` 142 | **1,149** | Ball detection, motion sampling, audio transients, swing extraction, keyframes; track building, geometry, the six checkpoints, rollup, priority focus; and the empirical constants. **This is the whole risk.** |
| **D · UI, re-expressed in SwiftUI** | `app.js` 910, `filmroom.js` 778, `index.html` 707, css 1,058, `store.js` 222, `ai.js` 137 | ~3,812 | The canvas is the spec. SwiftUI is far more compact than HTML+CSS+JS for the same screens. `store.js` → files/Core Data; `ai.js` → `URLSession`. |

**The headline: 20% of the codebase is the part that matters, 18% is pure architectural tax that vanishes, and the largest single file is content.**

**The Xcode project already exists** — `ios/DugOut.xcodeproj` with `AppDelegate`, `ViewController`, `Info.plist`, asset catalog and app icon. Project setup, bundle ID and icons are done. This is not a from-zero start.

---

## 3. The finding that settles it: the app is grading two checkpoints from noise

`js/pose.js` documents its own defect in its header comment. Quoting the repo:

- MoveNet SinglePose.Lightning takes a **192×192** input.
- The batter fills **~10% of frame width**, so MoveNet sees him **~19 px wide**.
- **Wrists score ~0.3** — the comment's own word for this is *noise*.
- A **two-pass crop-and-rerun** hack was built to roughly double wrist and elbow confidence.
- **"CT-05/CT-06 are *defined* on elbow-vs-wrist geometry."**

So two of the six checkpoints are computed from keypoints the code itself calls noise, and the product renders two confident PASS/FAIL marks anyway. **That is the charter's failure mode, in the repo, in a comment, written down and shipped.**

Two more costs recorded in the same file:
- **First inference costs ~12.5 seconds** (WebGL shader compile). The code burns it on a blank canvas at startup so it never lands on the user's first swing.
- If WebGL fails it falls back to the CPU backend — *"slow, but better than nothing."*

### What this does to R-15

R-15 says `CONTACT_ANCHOR: 0.62` is not honoured, measured at 0.500 / 0.761 / 0.572. I had attributed that to frame timing through a proxy codec. **That is at most half the story.** Contact is judged on wrist geometry, and wrist confidence is ~0.3. The anchor is inconsistent partly because its inputs are noise.

**`VNDetectHumanBodyPose` removes the cause, not the symptom:** full native resolution rather than a 192×192 squeeze, GPU-accelerated, first-party, no model shipped, no shader compile, no two-pass crop hack. The 19-pixel problem does not exist because nothing is downscaling the frame to make it.

Combined with `AVAssetReader` giving real presentation timestamps, the native pipeline fixes the *class* of bug that produces R-14 and R-15 rather than tuning around it.

### Also still live

`js/config.js:141` — `DEBUG: true // logs detection confidence for threshold tuning`. An open **R-13** violation (DUG-153). In a rebuild it simply never gets written.

---

## 4. The order of work

The order matters more than the decision. **Pipeline first, screens second.** The pipeline is where the risk and the hard-won knowledge are; screens are where the certainty is.

### Phase 0 — protect what works
The JS version stays on `main` as the **reference implementation**. Native work goes on its own branch. The Pages demo keeps running until native matches it. **Nothing is deleted to prove something new works.**

### Phase 1 — the pipeline, headless, no UI
Build in Swift, with no screens at all:
- `AVAssetReader` frame extraction with real presentation timestamps
- `VNDetectHumanBodyPose` in place of MoveNet (`pose.js` is deleted, not ported)
- Port `segment.js`: motion sampling, ball detection, audio transients, swing extraction, keyframes
- Port `evaluate.js`: track building, geometry, the six checkpoints, rollup, priority focus
- `config.js` constants transfer verbatim **as starting values, not as answers**

**Acceptance gate — this is the whole bet:** run the native pipeline against the same clips the JS version runs on, and compare swing counts and per-checkpoint results. If native reproduces or beats JS on the same footage, the rebuild is de-risked before a single screen exists. If it does not, that is learned in phase 1 rather than month four.

**Byproduct:** this is where **R-14 is finally confirmed on device** and **R-15 is diagnosed properly** — real timestamps and real keypoints, measured once rather than argued about.

### Phase 2 — capture
`AVCaptureDevice` at 120/240 fps. This is what was ruled, and it closes DUG-35's real requirement rather than its webview workaround.

### Phase 3 — screens in SwiftUI, from the canvas, with today's changes built in
The 29-artboard canvas remains the spec; design decisions are implementation-independent and survive the rewrite intact. Three changes from `ux-evidence-base.md` are built in from the start rather than retrofitted:

- **`A-STREAKS`** — streak the **behaviour** ("4 rounds in a row"), never the outcome. Per-checkpoint history becomes a mark strip. (§7)
- **`P-ROUND`** — the trend column is a mark strip, never "passed 6 straight" or "3rd round in a row". (§7)
- **`P-ROUND-START`** — carries the pre-round mastery line: *"Last round it was contact. Let's see it out front."* (§2)

And the capture entry points resolve cleanly now that capture is native — **this reconciles DUG-156 with §10**:
- **Rounds carries exactly two capture controls:** one **Record** (native, DUG-156's "one record button, on Rounds, and it works") and one **Upload** (handles one swing or a full round, per DUG-34, with *"one swing or a whole round"* as helper text).
- **Film watches only.** Empty Film points at Rounds.
- *"Just one swing"* and *"Choose video"* do not exist as separate entry points.

### Phase 4 — paywall and store
Apple IAP, one tier (R-26). The native app also removes the App Store 4.2 "minimum functionality" rejection risk that a webview wrapper carries — the plan had budgeted for one rejection.

---

## 5. Open decisions, in the order they bite

**None of these is ruled.** Anything citing a number below is citing a question,
not an answer.

### 5.1 v1 screen scope — RULED 2026-10-20 (CANON R-47)

**v1 is 21 of the 29 artboards.** Derell, 2026-10-20: *"Don't keep any of them.
Ship what we got, test, then determine if changes are needed."*

**IN — 21.** Parent (17): P-SPLASH, P-WELCOME, P-CONSENT, P-PROFILE-NEW,
P-PHILOSOPHY-PICK, P-ROUNDS-EMPTY, P-ROUND-START, P-CAGE, P-SEGMENTING, P-ROUND,
P-CHECKPOINT, P-REEL, P-CELEBRATE, P-PROGRESS, P-YOU, P-BILLING, P-DELETE.
States (4): S-NO-SWINGS, S-PARTIAL, S-OFFLINE, S-TRIM.

**OUT — 8.** P-ACCOUNT · P-LINK-COACH · A-FOCUS · A-REEL · A-STREAKS ·
A-EXCLUDED · S-CADENCE · S-FREE-LIMIT.

Every screen left is on the path from opening the app to seeing one fix, plus
the four failure states that actually occur. **This unblocks §5.4.**

Four consequences travel with it, set out in CANON R-47: no athlete-facing mode
at v1 (so `ux-evidence-base.md` §7's behaviour-streak change is deferred with
A-STREAKS, while §2's and §7's P-ROUND and P-ROUND-START changes ship); R-39
is deferred rather than resolved; R-26 is confirmed; and **P-ACCOUNT's removal
implies no Sign in with Apple at v1, which is opened as R-48 rather than banked
silently** — a screen cut must not become an architecture ruling by inference.

### 5.2 Where the native work lives — settled in practice

A new target in `ios/DugOut.xcodeproj` rather than a fresh project, so the bundle
ID, icons and the App Store Connect record (DUG-106) carry over untouched.
*Phase 1 built it this way (`ios/DugOutCore`, linked into the existing project),
so this is now description rather than decision.*

### 5.3 What happens to the Pages demo at cutover — UNRULED

It currently **is** the product: free, complete, to anyone with the URL, which
quietly undercuts R-26. It should become marketing-and-login on the day native
ships — not before, because it is the only working build until then.

### 5.4 The Jira board — UNBLOCKED 2026-10-20

It describes a webview product and needs re-cutting against this plan. It was
blocked on 5.1 from 2026-10-14; **5.1 is now ruled, so the re-cut can start.** The Oct 14 S02 plan is also
stale for the same reason and should not get the go in its current form.

### 5.5 February 14 — set aside, not cancelled

Set aside as a constraint on the architecture decision. It returns as a planning
input once phases 1–4 are sized into one-week sprints.

---

## 6. CANON changes this creates

| Ruling | Change |
|---|---|
| **R-07** no build step | **RETIRED.** Governed the web bundle; false for a native app. |
| **R-14** `SPIKE_ENTER_MULT` 2.4, PROVISIONAL | Confirmation moves into phase 1, measured with real timestamps. |
| **R-15** `CONTACT_ANCHOR` not honoured | **Diagnosis amended:** frame timing *and* ~0.3 wrist confidence from a 192×192 model on a 19-px subject. Native addresses both. |
| **R-13** never-log list | `DEBUG: true` is a live violation in the JS build; in native it is never written. |
| **NEW** | *DugOut is a native iOS app. The website is marketing, information and login only, and never the product.* |
| **NEW** | *Pose estimation uses the platform's on-device Vision framework. No pose model ships in the app.* |
| **NEW** | *Payment is StoreKit 2 in-app purchase, one tier (R-26). No web checkout, no card form drawn by the app, no receipt-validation server.* |
| **NEW** | *DugOut has exactly two capture entry points — one Record and one Upload. A single swing is a round of one (DUG-34). Film watches; it never captures.* |

All six are **blocked on the Jira gate** and should land together once the board is re-cut.

---

## 7. Payment — RULED: StoreKit 2 in-app purchase

**RULED (Derell, 2026-10-14):** payment is **StoreKit 2 in-app purchase inside the native app.** One tier, per R-26. No web checkout at v1.

### What was checked, not recalled

App Store payment rules moved materially in 2025–26, so the current state was verified rather than assumed (sources below; **re-verify before submission — this is live litigation, not settled law**).

- **US storefront link-out is permitted today, needs no entitlement, and Apple currently takes 0%.** Guideline 3.1.1(a) was amended after the Epic anti-steering ruling. Outside the US it remains prohibited without an entitlement — irrelevant here, since **US-only was ruled Oct 8**.
- **Apple petitioned the court on 2026-08-13** for commission on US link-outs: **15% standard, 5% Small Business Program, 10% on subscription renewals.** Pending before Judge Gonzalez Rogers, N.D. Cal. Not approved, not in effect.
- **In-app, Small Business Program: 15% from the first billing cycle** (30% without it).

### The arithmetic at $99/yr

| Route | Apple | Processor | **Kept** |
|---|---|---|---|
| In-app, Small Business Program | 15% ($14.85) | — | **$84.15** |
| Web checkout, today | 0% | Stripe 2.9% + $0.30 ($3.17) | **$95.83** |
| Web checkout, if the proposed 5% lands | 5% ($4.95) | $3.17 | **$90.88** |

Roughly **$12 per subscriber per year** in favour of web checkout today, falling to ~$7 if the proposal is approved.

### Why in-app anyway

1. **Web checkout makes DugOut the merchant of record.** Sales tax nexus across the states, renewals, failed-card retries, refunds, chargebacks — all of which Apple currently absorbs. That is ongoing operational load on a solo operator at 3 hrs/day, forever, not a one-time build cost.
2. **It requires the backend that R-27 defers.** Entitlement sync between a web purchase and the app needs a server. StoreKit 2 needs none: `Transaction.currentEntitlements` is JWS-verified on device, which is also the only option consistent with offline-first (R-28, sync off by default).
3. **Conversion.** Web checkout must convert at roughly 90% of in-app to break even. In-app is two taps and Face ID; a web form is not, least of all standing in a batting cage.
4. **Twelve dollars a head does not buy a backend, tax liability and a launch-day conversion hit.**

### Consequences for the build

- **StoreKit 2, one product, no receipt-validation server.** Lands in **Phase 4**, not earlier — it is the least risky part of the rebuild and gates nothing.
- **DUG-51 (Small Business Program approval) is on the payment critical path.** It is the difference between 15% and 30%, and it is currently waiting on Apple. It was already blocking S01; it now blocks a revenue parameter, not just paperwork.
- **The billing screen must be re-drawn against what StoreKit actually does.** The canvas's billing artboard was already flagged once in review for carrying **a fabricated billing mechanic**. StoreKit means Apple's own purchase sheet, Apple's receipt, and a deep link to Settings for managing or cancelling the subscription — the app does not draw its own card form or cancel flow. Drawing one would be the same defect again.
- **A free trial is not a free tier.** R-26 bars a free tier; StoreKit introductory offers are a separate question and remain **unruled**. Flag, do not assume.

### Revisit trigger, recorded so it is not forgotten

Reopen web checkout when **all three** hold: a backend exists (post-R-27), renewal volume makes 12% material, and the court has settled the link-out rate. Until then this ruling stands.

**Sources**
- Built by Foundry, *Can Your App Link Out to Your Own Checkout? 6 Rates for 2026* — https://www.builtbyfoundry.io/blog/app-link-out-checkout-6-rates-2026
- TechCrunch, 2026-08-14, *Apple proposes to take a 15% cut of purchases made outside the App Store* — https://techcrunch.com/2026/08/14/apple-proposes-to-take-a-15-cut-of-purchases-made-outside-the-app-store/
- RevenueCat, *What Epic v. Apple's anti-steering ruling means for developers* — https://www.revenuecat.com/blog/growth/apple-anti-steering-ruling-monetization-strategy

---

## 8. Imagery — the standard, and the gate nobody has ticketed

**Raised by Derell, 2026-10-14:** *"the shadow figure looks horrible and is not production ready. please ensure before we go live this is high quality."*

### 8.1 What went wrong with the sprite, measured

`shadow-sprite.jpg` is a **288×191-per-frame downsample of `swing-shadow.mp4`, which is 720×478** (h264, 326 frames, 10.9s). A quarter of the source resolution, with the green field background **baked into every frame** so it cannot be keyed, recoloured, or composited. The canvas then scales it back up. It was never going to survive review, and it should not have gone onto the canvas without that being said out loud.

**Where it ships: nowhere.** In the product, the Film player shows the athlete's actual clip and every thumbnail is a real frame from his round. No silhouette exists anywhere in the app. The sprite is mockup furniture only.

**That is not a defence.** The canvas is the spec Derell reviews and the SwiftUI build is written from. A placeholder that looks cheap teaches a cheap floor.

**RULED — placeholder imagery:**
> No stock, generic or low-resolution art appears on the design canvas or in the app. A mockup either shows real material at full quality, or it shows an honest empty treatment that does not pretend to be footage. A blurry silhouette standing in for a child's swing is the second thing dressed as the first.

**Remedy for the canvas (not yet done):** re-cut from the 720×478 source at full frame resolution with the background keyed, so frames composite on the field colour instead of carrying their own. 2.5× the pixels of the current sheet.

### 8.2 The real exposure: App Store screenshots show a minor

Searched every doc in the repo for `likeness`, `release form`, `photo release`, `screenshot`: **zero matches.**

App Store screenshots and the marketing site are the only places DugOut ships imagery to the public, and both will show a real swing, which means **a real child**. DUG-52 covers the listing. Nothing covers:

1. **Who appears** in the screenshots and marketing footage.
2. **Whether their parent has signed a likeness release** — a written one, retained.
3. **Whether a child's face appears at all**, or whether the product markets itself on framing that does not identify anyone.
4. **Where those assets are stored** and under what retention.

**This is a submission gate, not a nice-to-have.** Apple will not accept a listing without screenshots. And for a product positioned on "we are careful with your kid," publishing a minor's likeness without a retained written release is the single worst place in this business to be careless. It also sits awkwardly beside R-30 (pose keypoints are biometric) and the COPPA posture memo, which were both written with exactly this kind of care.

**Candidate CANON ruling, not yet ruled:**
> No identifiable minor appears in any public-facing DugOut asset — App Store screenshots, website, social, or press — without a written likeness release signed by a parent or guardian and retained. Where no release exists, public assets use framing that does not identify the athlete. This is a submission gate on DUG-52.

**Open, for Derell:**
- Does a release exist for anyone in the existing `pitch_01–06.mov` test clips? (They live in the OneDrive folder, not the repo — `media/` is gitignored.)
- Does v1 market with an identifiable child at all, or with non-identifying framing?
- Claude will not publish frames of a real child into a cloud artifact until this is ruled.
