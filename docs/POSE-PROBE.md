# Pose & segmentation probe — measured findings

Run July 16 2026 against the real footage in the working folder (`media/`), before
building DUG-34. Everything below is measured in a browser, not estimated.
Numbers matter because segmentation quality is the #1 technical risk.

## Test material

| Clip | Duration | Notes |
|---|---|---|
| `media/test-clips/pitch_01–06.mov` | ~23s each | one swing per clip → "session of one" material |
| `media/IMG_0768.mov` | 170.1s | full round, over the 90s cap |
| `media/IMG_0769.mov` | 115.1s | full round, over the 90s cap |

All are **1920×1080 HEVC (hvc1) + AAC**, shot in a backyard (not a cage), single
subject in frame, camera side-on and far back.

## What works

- **HEVC decodes in-browser.** No transcode needed on Safari/Chrome. Firefox is patchier.
- **MoveNet SinglePose.Lightning loads from vendored local files** (`vendor/movenet/`) on
  the WebGL backend — no CDN, no build step, works offline.
- **It locks onto the batter,** not the background. 17/17 keypoints > 0.3 through the swing.
- **Inference is fast enough:** ~11–31 ms/frame after warmup.

## What bites

**1. First inference costs ~12.5s** (shader compile), then drops to ~11ms. Warm the model
during segmentation, never on the user's first swing.

**2. The subject is small in frame — crop before you trust the joints.**
The batter occupies ~10% of frame width (bbox 100px of 960), so MoveNet's 192×192 input
sees him ~19px wide. Fine joints suffer. Re-running pose on a padded square crop of the
batter's bbox, upscaled to 256, roughly doubles wrist confidence:

| t | wrist (full frame) | wrist (cropped) | elbow (full) | elbow (cropped) |
|---|---|---|---|---|
| 19.9 | 0.33 / 0.37 | **0.69 / 0.76** | 0.39 / 0.37 | **0.59 / 0.60** |
| 20.2 | 0.37 / 0.40 | **0.68 / 0.64** | 0.53 / 0.24 | **0.75 / 0.61** |
| 20.5 | 0.28 / 0.48 | **0.81 / 0.81** | 0.43 / 0.25 | **0.69 / 0.46** |
| 20.8 | 0.28 / 0.26 | **0.70 / 0.49** | 0.47 / 0.25 | **0.63 / 0.64** |

Mean keypoint score: 0.47–0.51 full frame → 0.58–0.63 cropped.

This is not optional. CT-05 (casting = "elbow outside the hands") and CT-06 (bat drag =
"rear elbow in front of the hands") are *defined* on elbow-vs-wrist geometry. At 0.25
elbow confidence those calls would be noise. **Pose must be two-pass: detect → crop → re-detect.**

**3. Seek-sampling is too slow for a round.** Deterministic seeking cost **37 ms/frame**
(1080p HEVC, desktop). A 90s round at 30fps = 2700 frames ≈ **100s of processing** — worse on a
phone. Production must sample via playback + `requestVideoFrameCallback`, which runs at
native cadence and can be driven at `playbackRate > 1`. Keep seeking only for on-demand
frame extraction (Deep Dive, Chalk), where it's a handful of frames.

**4. Sampling off the native frame rate aliases.** Sampling at 20fps against 30fps footage
makes consecutive samples land on the *same* decoded frame, so the motion-energy signal
alternates high/low and fragments any threshold crossing. Detect native fps (via rVFC
`meta.mediaTime` deltas) and sample on frame boundaries, not wall-clock intervals.

**5. Motion energy alone under-segments.** On `pitch_01.mov` the energy has real structure
(max/median = 7.9) but a naive `4×median` threshold found only 1 spike across a clip with
two visible activity clusters — because of the aliasing in (4) and because the signal is
noisy. Motion is the primary signal per spec, but it needs smoothing + hysteresis, and
audio transients as confirmation.

**6. The bat is never tracked.** MoveNet has no bat keypoint, and the bat is thin, fast, and
motion-blurred. Any fault defined on the barrel — FN-01 (barrel decelerating into contact),
CT-04 (attack angle) — cannot be measured from pose alone. These stay honest gaps unless we
add dedicated bat detection.

## Environment note

The Claude preview pane renders occluded, so Chrome refuses to play or paint video there
(`play()` resolves, then `currentTime` stays 0 and `requestVideoFrameCallback` never fires).
That's a harness artifact, not an app bug — but it means **the playback+rVFC path cannot be
verified in this sandbox** and must be checked on a real device.

## Vendored dependencies

Committed under `vendor/`, ~5.6MB total, no CDN and no build step:

| File | Size | Source |
|---|---|---|
| `tf-core.min.js` | 294 KB | jsdelivr `@tensorflow/tfjs-core@4.22.0` |
| `tf-converter.min.js` | 323 KB | jsdelivr `@tensorflow/tfjs-converter@4.22.0` |
| `tf-backend-webgl.min.js` | 399 KB | jsdelivr `@tensorflow/tfjs-backend-webgl@4.22.0` |
| `pose-detection.min.js` | 73 KB | jsdelivr `@tensorflow-models/pose-detection@2.1.3` |
| `movenet/model.json` + 2 shards | 4.6 MB | `tfhub.dev/google/tfjs-model/movenet/singlepose/lightning/4` |

Note the model is fetched from tfhub.dev with `?tfjs-format=file`; the older
`storage.googleapis.com/tfjs-models/...` path now 404s after the Kaggle migration.

## Addendum — what the preview sandbox cannot verify (July 16)

The Claude preview renderer is occluded, and the consequences are broader than first
recorded. Measured, not assumed:

- `play()` resolves but `currentTime` stays 0 and no frames paint.
- `requestVideoFrameCallback` never fires → segmentation falls back to seeking.
- **`requestAnimationFrame` never fires.**
- **`ResizeObserver` never fires** — a fresh observer with a forced layout change delivered
  zero callbacks.
- A freshly-served CSS rule failed to apply to a canvas (`#overlay{width:100%}` present in
  the loaded sheet, computed width stayed at the intrinsic 300px).

Two things follow. First, anything whose *correctness* depends on the render loop must not
rely on it alone — `sizeCanvas()` now retries on a timer rather than rAF, and the chalk
overlay is sized from CSS so alignment does not wait on JS. This is a real robustness win
on device too: a backgrounded phone tab stops painting for the same reason.

Second, these remain **unverified and must be checked on a real phone**:

1. The playback + rVFC segmentation path (the fast path; only the seek fallback ran here).
2. Chalk overlay alignment over a stored swing's keyframes.
3. The checkpoint shadow-sprite animations (they are driven by rAF).
4. The timed in-app round (`getUserMedia` + `MediaRecorder`) — no camera here.
5. Any AI path — no backend reachable from the static demo.

### Performance, measured

The seek fallback processed a 23.3s clip in ~200s (~490ms/sample across 348 samples) —
far worse than the 37ms/frame the standalone probe measured for seeking alone. The likely
cause is contention with the live WebGL context, since MoveNet is loaded before the motion
pass to find the batter ROI. This does not affect the playback path, which is what a phone
will use, but it means **the fallback is not a viable primary path** and the rVFC route has
to be confirmed on device before the trainer demo.
