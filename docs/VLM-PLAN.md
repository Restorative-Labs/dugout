# DugOut — Realtime VLM Swing Feedback: Plan v1.0

**Date:** 2026-08-30 · **Jira:** DUG-50 (A24) · **Research current as of 2026-08-30**
**Companion to:** `DugOut_MVP_Definition_and_Release_Ladder_v1.0.md`

---

## 1. The headline, before anything else

**True in-swing realtime feedback is not achievable in 2026, by us or by anyone.** A baseball swing from forward initiation to bat-ball impact is **130–280 ms**. Network round-trip alone exceeds that. No hosted frontier model accepts streaming video above **1 frame per second** — including Gemini's Live API, which is documented as "images (JPEG ≤1FPS), text." At 1 FPS a swing yields, at most, one frame.

**Nobody in the category is doing it either.** Every "instant feedback after every swing" claim — WIN Reality SwingAI included — is between-swings processing after upload. Checked: WIN Reality/Blast, Athletech Baseball AI, b4-app ("Coach Areo"), PitchLab, Diamond Kinetics SmartMotion, Uplift Labs, Theia3D. The only genuinely realtime products in the space are **bat-mounted IMU sensors over Bluetooth**, which is inertial sensing, not vision.

So the question isn't "can we do realtime." It's **which latency tier is the product**, and the answer is clear:

| Tier | Latency | Feasible | Verdict |
|---|---|---|---|
| **(a) In-swing** | <200 ms, mid-swing | ❌ Not with any LLM in the loop | Only as an on-device pose threshold firing a tone or haptic. Interesting later, not a product |
| **(b) Between-swings** | **2–6 s, while the hitter resets for the next pitch** | ✅ **Today** | **This is the product.** It matches the cage rhythm exactly — a JUGS carousel feeds a ball every ~6 s |
| **(c) End-of-session** | 30 s – minutes | ✅ | What we ship at R1. Keep it as the session summary; batch pricing is 50% off |

**The 6-second JUGS cadence is the whole design brief.** Feedback that lands before the next ball arrives is coaching. Feedback that lands after it is a report.

---

## 2. The architecture — and the one rule that must not bend

> **The vision model never decides PASS/FAIL. It selects and voices an existing Tip Library entry from verdicts we already computed deterministically.**

This is not caution. It is the finding of every serious 2026 result on the subject.

### The evidence

- **The documented failure (2025-11-19).** Gemini 3, used as a junior golf swing coach, invented three faults that were not in the video — a bent lead arm at the top, overswinging, early extension — while the lead hip was in fact "clearing perfectly." The mechanism matters more than the anecdote: *the model reads "give me tips" as "find a problem so I can offer a solution." If a problem doesn't exist, it hallucinates one.*
- **MoHallBench (arXiv 2607.01117, Jul 2026)** — 11,306 clips measuring *motion* hallucination in video LLMs. With videos truncated before the outcome, accuracy fell to **~5% at 50% truncation and toward zero at 70%**. Models confabulate the completion of a partially-seen motion. **That is exactly our case** — we feed segmented swing clips.
- **SportsGPT (Springer/arXiv 2512.14121)** independently converged on our architecture: pose estimation → keyframe alignment → a **deterministic kinematic-anomaly→problem mapping matrix** → retrieval over a **closed knowledge base** → LLM for phrasing only. Raw biomechanics never reach the model. It beat GPT-5 and Claude 4.5 in double-blind expert scoring.
- **PoseForge (arXiv 2608.05971, Aug 2026)** — same pattern, plus every suggestion validated against kinematic constraints and **rejected if infeasible**.

**The strategic read: the Tip Library isn't just a content asset and a marketing claim. It is the technically correct grounding layer, and the field has now published that conclusion.** DUG-37 is more defensible today than it was in July.

### The pipeline

```
Native capture (AVCaptureSession, 120–240 fps)
        │
        ├─► on-device pose (Vision / MoveNet) ──► joint series
        │
        ├─► deterministic checkpoint engine (evaluate.js)
        │        └─► six internal scores → PASS/FAIL vs thresholds
        │            → fault IDs → applicable Tip Library entries
        │            → priority focus
        │
        └─► 6–9 downscaled key frames per swing (≈640×360)
                     │
                     ▼
        ┌────────────────────────────────────────────┐
        │  VLM call — via js/ai.js, via our proxy    │
        │                                            │
        │  IN:  the six verdicts (already decided)   │
        │       the candidate tip IDs                │
        │       the philosophy's cue vocabulary      │
        │       red lines / cues-to-avoid            │
        │       the key frames (confirmation only)   │
        │                                            │
        │  OUT: chosen tip ID + phrasing             │
        │       (constrained to the candidate set)   │
        └────────────────────────────────────────────┘
                     │
                     ▼
        Render in the coach's voice, drill attached
```

**Guardrails that must be built, not assumed:**
1. Output is constrained to **selecting a tip ID from the supplied candidates**. A tip ID not in the set is a rejected response, not a creative one.
2. An explicit **all-six-passed path**, so the model is never rewarded for finding a fault. This is the direct antidote to the documented failure mode.
3. **Red lines are enforced in code**, not in the prompt. If a coach has banned "swing down", the string never renders, whatever the model returns.
4. **The deterministic stub stays.** With no key, no network, or a rejected response, the app still segments, evaluates and renders from the library. This is already an invariant in `CLAUDE.md` — keep it.

---

## 3. Model selection and cost

**Assumptions:** 15 swings/session × 9 key frames = 135 frames; ~1,500 tokens of rubric + candidate tips per swing call; ~200 output tokens/swing.

| Model | Frame size | Total in-tokens | **Cost / session** | Notes |
|---|---|---|---|---|
| Claude Haiku 4.5 | 640×360 (299 tok) | 62,865 | **$0.078** | ~$0.046 with prompt caching (cache reads at 0.1× input) |
| Claude Haiku 4.5 | 1280×720 (1,196 tok) | 183,960 | $0.199 | 4× the area = 4× the cost |
| Claude Sonnet 5 | 640×360 | 62,865 | $0.156 | |
| Gemini 3.1 Flash-Lite | low-res (66 tok) | 31,410 | **$0.012** | Cheapest credible option |
| Gemini 3.1 Flash-Lite | default (258 tok) | 57,330 | $0.019 | |
| Gemini 3.7 Flash | default | 57,330 | $0.054 | ⚠️ doubles to $0.108 on 2027-01-01 |
| Claude Opus 5 | 1280×720 | 183,960 | $0.995 | Never, for this |

**Three things fall out of this table:**

1. **Frame resolution dominates cost, not model choice.** Going from 640×360 to 1280×720 costs 4× on every model. Downscale hard; the checkpoints are gross-motor, not fine-detail.
2. **Every option clears margin comfortably.** At 13 sessions/user/month: Haiku small-frame ≈ **$1.01/user/mo** (~$0.60 cached), Gemini Flash-Lite ≈ **$0.16/user/mo**, against $14.99/mo revenue. The July model's $0.17–0.20/session hybrid estimate holds up and is, if anything, conservative.
3. **Prompt caching is the single biggest lever we're not using.** The rubric and the candidate tip corpus are identical across every swing in a session and across most sessions. Cache them.

**Recommendation: Claude Haiku 4.5 at 640×360 with prompt caching, behind our own proxy.** Reasons: latency (~0.6–0.84s TTFT fits the between-swings budget with room), the phrasing quality is the whole point and Haiku is materially better at voice than a Flash-Lite tier, and the cost delta ($0.046 vs $0.019/session) is noise against $14.99/mo. Keep Gemini Flash-Lite specified as the cost-down fallback if session volume per user turns out much higher than modeled.

**Note on Claude and video:** Claude has no native video input. Frame extraction is the only path — which is fine, because we want to choose the frames anyway. The checkpoint moments *are* the frames.

---

## 4. What has to be built first

The VLM layer is worthless without native capture underneath it. Ordered:

| Step | What | Why it's a prerequisite | Release |
|---|---|---|---|
| 1 | **Native `AVCaptureSession` capture at 120–240 fps** | `getUserMedia` in WKWebView gives no frame-rate guarantees. Coaching guidance is 120 fps for human review, **240 fps when AI will analyze it**, to kill motion blur on the bat. Also required anyway for App Review 4.2 (DUG-45) | R2 |
| 2 | **JS↔native bridge via `WKScriptMessageHandler`** | Push **joint arrays and verdicts** into JS, never pixels. The old pattern of streaming YUV over a local WebSocket cost 15–20 ms at 1080p and capped at 20–30 fps — don't | R2 |
| 3 | **Per-swing evaluation, not per-session** | Today the engine evaluates the session. Between-swings feedback needs a per-swing determination path with a session-level rollup | R3 |
| 4 | **AI proxy** (DUG-49) | Per-user pasted keys cannot be metered, rotated or cost-controlled. Gates any shipped AI | R3 |
| 5 | **Prompt caching + constrained tip-ID output** | The cost and safety layer | R3 |
| 6 | **Between-swings UI** | Big, one-line, readable from a cage floor between pitches. Never blocks the next swing | R4 |

---

## 5. On-device: the option worth watching, not betting on

- **Apple Vision framework** (`VNDetectHumanBodyPoseRequest`, and 3D since iOS 17) is mature, free, and better than MoveNet-in-JS for this. Migrating pose to native is a straightforward win once the bridge exists.
- **Apple FastVLM** (0.5B/1.5B/7B) is the realistic on-device VLM — 85× faster time-to-first-token than LLaVA-OneVision-0.5B, with a shipping demo running the 0.5B on iPhone 16 Pro at "near real-time." No published exact latency figure.
- **Foundation Models framework** gained **image input at WWDC26 (2026-06-08)** — `Attachment(UIImage/CGImage/CVPixelBuffer)` — plus a Private Cloud Compute tier and a `LanguageModel` protocol that lets Anthropic's `ClaudeForFoundationModels` package drop in as a provider. **No video input.** Requires **iOS 27**, still in beta as of Aug 2026, shipping "late 2026," and Apple Intelligence needs A17 Pro or later (iPhone 15 Pro+).

**Why we don't bet on it:** our users are youth-sports families, and an A17-Pro-or-newer floor cuts out a large share of them. The cloud path costs ~$0.05/session and works on every phone. Revisit in mid-2027 when the hardware base has moved — the win then is offline coaching in a cage with no signal, which is a real product advantage, not just a cost saving.

---

## 6. Phasing

| Phase | Release | Ships | Latency |
|---|---|---|---|
| **P0 — today** | R1 | End-of-session determination, deterministic, library-composed, offline-capable | (c) |
| **P1** | R2 | Native 120–240 fps capture + native pose + the bridge. **No VLM yet** — this is infrastructure and 4.2 compliance | (c) |
| **P2** | R3 | Per-swing evaluation + VLM phrasing layer behind the proxy, with caching and constrained output. Still surfaced at session end | (c), fast |
| **P3** | R4 | **Between-swings feedback in the cage.** One line, 2–6 s after each swing | **(b)** ← the goal |
| **P4** | 2027+ | On-device pose thresholds → immediate haptic/tone on a red-line fault. No LLM in the loop. Optional on-device VLM if the hardware base allows | (a)-adjacent |

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| **The model hallucinates a fault anyway** | Constrained tip-ID output + explicit all-passed path + code-enforced red lines. Test adversarially with clean swings and assert nothing is found |
| **Between-swings latency slips past 6 s in the field** | Measure end-to-end on a real cage round on cellular, not on wifi at a desk. If it slips, degrade to a mark rather than a sentence |
| Gemini 3.7 Flash pricing doubles 2027-01-01 | Not our primary. Noted so the model doesn't get chosen on a stale number |
| Apple commission compresses margin | Separate issue (DUG-53), but it's the same P&L. Inference cost is not the constraint; the App Store cut is |
| **Building this before segmentation is reliable** | The hard sequencing rule: **DUG-34 has to be boringly correct before a model is asked to comment on its output.** Feeding a VLM mis-segmented clips produces confident nonsense and burns the trust the whole product runs on |

---

## Sources

Anthropic pricing & vision token math (`platform.claude.com/docs/en/about-claude/pricing`, `/build-with-claude/vision`) · Gemini API pricing, Live API and video-understanding docs (1 FPS cap) · OpenAI API pricing and Realtime guide (no vision) · Frontiers in Sports & Active Living 2025, bat-ball impact timing · CoachNow, frame rates for swing capture · ChromeUnboxed 2025-11-19, Gemini 3 golf-coach hallucination · MoHallBench arXiv 2607.01117 · SportsGPT arXiv 2512.14121 · PoseForge arXiv 2608.05971 · Apple: FastVLM research, WWDC26 session 241 (Foundation Models), `VNDetectHumanBodyPose3DRequest`, WWDC21-10032 (WKWebView media capture) · WIN Reality SwingAI, Blast Motion acquisition (Business Wire 2025-06-23), AWRE partnership · Athletech Baseball AI · b4-app · Uplift Labs · Theia markerless bat tracking
