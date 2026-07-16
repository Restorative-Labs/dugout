// Dugout — pose estimation (MoveNet SinglePose.Lightning, vendored, offline).
//
// Two-pass by necessity, not preference. Measured on the real footage: the batter fills
// ~10% of frame width, so MoveNet's 192x192 input sees him ~19px wide and wrists score
// ~0.3 — noise. Re-running on a padded crop of his bbox roughly doubles wrist and elbow
// confidence, and CT-05/CT-06 are *defined* on elbow-vs-wrist geometry. See docs/POSE-PROBE.md.
(function () {
  const CFG = window.DUGOUT_CONFIG;

  let detector = null;
  let warming = null;

  const work = document.createElement('canvas');
  const wctx = work.getContext('2d', { willReadFrequently: true });
  const crop = document.createElement('canvas');
  crop.width = crop.height = CFG.POSE_CROP_SIZE;
  const cctx = crop.getContext('2d', { willReadFrequently: true });

  async function load(onProgress) {
    if (detector) return detector;
    if (warming) return warming;
    warming = (async () => {
      if (typeof tf === 'undefined' || typeof poseDetection === 'undefined') {
        throw new Error('Pose libraries did not load.');
      }
      if (onProgress) onProgress('Waking up the coach’s eye…');
      try {
        await tf.setBackend('webgl');
      } catch (e) {
        await tf.setBackend('cpu');   // slow, but better than nothing
      }
      await tf.ready();
      detector = await poseDetection.createDetector(poseDetection.SupportedModels.MoveNet, {
        modelType: 'SinglePose.Lightning',
        modelUrl: CFG.MODEL_URL
      });
      // First inference costs ~12.5s (shader compile). Burn it on a blank canvas now so it
      // never lands on the user's first swing.
      if (onProgress) onProgress('Warming up…');
      work.width = work.height = 256;
      wctx.fillStyle = '#000';
      wctx.fillRect(0, 0, 256, 256);
      try { await detector.estimatePoses(work); } catch (e) { /* warmup only */ }
      return detector;
    })();
    return warming;
  }

  const kp = (pose, name) => pose && pose.keypoints.find((k) => k.name === name);
  const ok = (pose, name) => {
    const k = kp(pose, name);
    return k && k.score >= CFG.POSE_MIN_SCORE ? k : null;
  };

  function bbox(pose) {
    const good = pose.keypoints.filter((k) => k.score >= CFG.POSE_MIN_SCORE);
    if (good.length < 4) return null;
    const xs = good.map((k) => k.x), ys = good.map((k) => k.y);
    return { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) };
  }

  // Estimate on a source (video/canvas), then refine on a crop around the subject.
  // Returns keypoints in SOURCE pixel coordinates so callers never see the crop.
  async function estimate(source, sw, sh) {
    const det = await load();
    work.width = Math.round(sw);
    work.height = Math.round(sh);
    wctx.drawImage(source, 0, 0, work.width, work.height);

    const first = (await det.estimatePoses(work))[0];
    if (!first) return null;
    const bb = bbox(first);
    if (!bb) return first;

    // pass 2: square crop around the batter, upscaled — this is where the fine joints come from
    const cx = (bb.x0 + bb.x1) / 2, cy = (bb.y0 + bb.y1) / 2;
    const side = Math.max(bb.x1 - bb.x0, bb.y1 - bb.y0) * CFG.POSE_CROP_PAD;
    if (side < 8) return first;
    const sx = cx - side / 2, sy = cy - side / 2;
    cctx.clearRect(0, 0, crop.width, crop.height);
    cctx.drawImage(work, sx, sy, side, side, 0, 0, crop.width, crop.height);

    const second = (await det.estimatePoses(crop))[0];
    if (!second) return first;

    const scale = side / CFG.POSE_CROP_SIZE;
    const mapped = second.keypoints.map((k) => ({
      name: k.name,
      score: k.score,
      x: sx + k.x * scale,
      y: sy + k.y * scale
    }));

    // Keep whichever pass was more confident per joint — the crop usually wins, but if the
    // crop clipped a limb the full-frame estimate is the better answer.
    const merged = mapped.map((m) => {
      const f = first.keypoints.find((k) => k.name === m.name);
      return f && f.score > m.score ? f : m;
    });
    return { keypoints: merged, score: second.score, _w: work.width, _h: work.height };
  }

  // Geometry helpers shared by the detectors. All work in source pixels.
  const mid = (a, b) => (a && b ? { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 } : (a || b || null));
  const angleOf = (a, b) => Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI;
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

  window.DugoutPose = {
    load, estimate, kp, ok, bbox, mid, angleOf, dist,
    isReady: () => !!detector
  };
})();
