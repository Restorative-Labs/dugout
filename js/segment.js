// Dugout — round segmentation (DUG-34). The #1 technical risk; built and tuned first.
//
// Strategy, per spec: motion is primary, audio is confirmatory. The contact "ping" is a
// strong signal but swings-and-misses must still be caught, so a swing is never rejected
// for lacking audio — audio only sharpens the contact frame and adds confidence.
//
// Two hard-won details from probing the real footage (docs/POSE-PROBE.md):
//   1. Sampling off the native frame rate makes consecutive samples land on the SAME
//      decoded frame, so the energy signal alternates high/low and shreds any threshold.
//      Playback + requestVideoFrameCallback gives real frames at native cadence.
//   2. Seeking costs ~37ms/frame — a 90s round would take ~100s. Playback is the fast
//      path; seeking is only the fallback (and for keyframe extraction).
(function () {
  const CFG = window.DUGOUT_CONFIG;

  const mcv = document.createElement('canvas');
  mcv.width = CFG.MOTION_W; mcv.height = CFG.MOTION_H;
  const mctx = mcv.getContext('2d', { willReadFrequently: true });

  const kcv = document.createElement('canvas');
  const kctx = kcv.getContext('2d');

  function seekTo(v, t) {
    return new Promise((res, rej) => {
      let done = false;
      const ok = () => { if (!done) { done = true; v.removeEventListener('seeked', ok); res(); } };
      v.addEventListener('seeked', ok);
      v.currentTime = Math.max(0, Math.min(v.duration || 0, t));
      setTimeout(() => { if (!done) { done = true; v.removeEventListener('seeked', ok); rej(new Error('seek timeout')); } }, 8000);
    });
  }

  const OFFSCREEN = 'position:fixed;left:-9999px;top:0;width:160px;pointer-events:none;opacity:0.01';

  // MUST be called synchronously inside the tap that picks the file.
  //
  // iOS Safari only lets a <video> play as the direct result of a user gesture, and an
  // unplayed video also draws blank to canvas there. Every await between the tap and
  // play() spends the gesture — and this pipeline used to load a 5.6MB model first, so by
  // the time it called play() the gesture was long gone, playback was refused, and the
  // whole round fell into the seek fallback: ~200s for a short clip, i.e. an apparent hang.
  // Priming here starts playback while the gesture is still live; the element stays
  // unlocked for the rest of the round.
  function primeVideo(fileOrBlob) {
    const url = URL.createObjectURL(fileOrBlob);
    const v = document.createElement('video');
    v.muted = true;
    v.defaultMuted = true;
    v.setAttribute('muted', '');
    v.setAttribute('playsinline', '');
    v.playsInline = true;
    v.preload = 'auto';
    // Chrome will not decode or paint a detached <video>; it must be in the document.
    v.style.cssText = OFFSCREEN;
    document.body.appendChild(v);
    v.src = url;
    v._objectUrl = url;
    const p = v.play();
    if (p && p.catch) p.catch(() => { v._primeFailed = true; });
    return v;
  }

  function loadVideo(src) {
    return new Promise((res, rej) => {
      const v = document.createElement('video');
      v.src = src; v.muted = true; v.playsInline = true; v.preload = 'auto';
      v.setAttribute('muted', ''); v.setAttribute('playsinline', '');
      v.style.cssText = OFFSCREEN;
      document.body.appendChild(v);
      v.addEventListener('loadedmetadata', () => res(v), { once: true });
      v.addEventListener('error', () => rej(new Error('That video could not be read. Try a different clip.')), { once: true });
      setTimeout(() => rej(new Error('That video took too long to open.')), 30000);
    });
  }

  const ready = (v) => (v.readyState >= 1 ? Promise.resolve(v) : new Promise((res, rej) => {
    v.addEventListener('loadedmetadata', () => res(v), { once: true });
    v.addEventListener('error', () => rej(new Error('That video could not be read. Try a different clip.')), { once: true });
    setTimeout(() => rej(new Error('That video took too long to open.')), 30000);
  }));

  const releaseVideo = (v) => {
    try { v.pause(); } catch (e) { /* already gone */ }
    v.removeAttribute('src');
    v.load();
    if (v.parentNode) v.parentNode.removeChild(v);
  };

  // The batter ROI used to be found by posing three frames up front. It is gone: it forced
  // the 5.6MB model to load before the motion pass could start, delayed all progress, and
  // contended with video decode for the GPU. The standalone probe found the same two swings
  // in pitch_01.mov full-frame with no pose at all (max/median energy 7.9), so a swing
  // dominates wind-moving trees comfortably. Pose now loads lazily, after segmentation,
  // when the first swing is actually analyzed. Revisit if false positives show up on
  // busier footage — the fix is a motion heatmap, not pose.
  function grayInROI(v, roi) {
    mctx.drawImage(v, 0, 0, CFG.MOTION_W, CFG.MOTION_H);
    const x0 = roi ? Math.floor(roi.x0 * CFG.MOTION_W) : 0;
    const x1 = roi ? Math.ceil(roi.x1 * CFG.MOTION_W) : CFG.MOTION_W;
    const y0 = roi ? Math.floor(roi.y0 * CFG.MOTION_H) : 0;
    const y1 = roi ? Math.ceil(roi.y1 * CFG.MOTION_H) : CFG.MOTION_H;
    const w = Math.max(1, x1 - x0), h = Math.max(1, y1 - y0);
    const d = mctx.getImageData(x0, y0, w, h).data;
    const g = new Float32Array(w * h);
    for (let i = 0, p = 0; i < d.length; i += 4, p++) g[p] = d[i] * 0.299 + d[i + 1] * 0.587 + d[i + 2] * 0.114;
    return g;
  }

  // ---------- ball detection ----------
  //
  // Motion energy cannot tell a swing from a bat reset — both are just "movement", and on
  // real footage the reset actually wins (it is slower and more sustained). A ball crossing
  // the frame is what says a pitch happened. No ball, no swing.
  //
  // The ball is found as a small, isolated, consistently-moving blob in the frame diff:
  // too small to be the hitter, too persistent and too directional to be a leaf.
  const bcv = document.createElement('canvas');
  bcv.width = CFG.BALL_W; bcv.height = CFG.BALL_H;
  const bctx = bcv.getContext('2d', { willReadFrequently: true });

  function ballGray(v) {
    bctx.drawImage(v, 0, 0, CFG.BALL_W, CFG.BALL_H);
    const d = bctx.getImageData(0, 0, CFG.BALL_W, CFG.BALL_H).data;
    const g = new Uint8Array(CFG.BALL_W * CFG.BALL_H);
    for (let i = 0, p = 0; i < d.length; i += 4, p++) g[p] = d[i] * 0.299 + d[i + 1] * 0.587 + d[i + 2] * 0.114;
    return g;
  }

  // Connected components over the diff mask. Blobs bigger than a ball (i.e. the hitter) are
  // still fully traversed — they have to be, to mark them seen — but stop being tracked.
  const _stack = new Int32Array(CFG.BALL_W * CFG.BALL_H);
  function ballBlobs(cur, prev) {
    const W = CFG.BALL_W, H = CFG.BALL_H, N = W * H;
    const seen = new Uint8Array(N);
    const out = [];
    for (let p0 = 0; p0 < N; p0++) {
      if (seen[p0]) continue;
      if (Math.abs(cur[p0] - prev[p0]) <= CFG.MOTION_PIXEL_DELTA) { seen[p0] = 1; continue; }
      let sp = 0;
      _stack[sp++] = p0; seen[p0] = 1;
      let n = 0, sx = 0, sy = 0, x0 = 1e9, x1 = -1, y0 = 1e9, y1 = -1;
      while (sp > 0) {
        const q = _stack[--sp];
        const qx = q % W, qy = (q - qx) / W;
        n++; sx += qx; sy += qy;
        if (qx < x0) x0 = qx; if (qx > x1) x1 = qx;
        if (qy < y0) y0 = qy; if (qy > y1) y1 = qy;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            const nx = qx + dx, ny = qy + dy;
            if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
            const r = ny * W + nx;
            if (seen[r]) continue;
            if (Math.abs(cur[r] - prev[r]) <= CFG.MOTION_PIXEL_DELTA) { seen[r] = 1; continue; }
            seen[r] = 1;
            if (sp < _stack.length) _stack[sp++] = r;
          }
        }
      }
      if (n < CFG.BALL_MIN_AREA || n > CFG.BALL_MAX_AREA) continue;
      const bw = x1 - x0 + 1, bh = y1 - y0 + 1;
      const aspect = Math.max(bw / bh, bh / bw);
      if (aspect > CFG.BALL_MAX_ASPECT) continue;   // a long streak is an arm or a bat
      out.push({ x: sx / n, y: sy / n, area: n });
    }
    return out;
  }

  // Link per-frame candidates into trajectories. A ball flies in a consistent direction;
  // noise flickers in place, which BALL_MIN_DISP rejects.
  function linkBallTracks(frames) {
    const tracks = [];
    frames.forEach((f) => {
      f.blobs.forEach((b) => {
        let best = null, bd = CFG.BALL_MAX_JUMP;
        for (const tr of tracks) {
          if (tr.closed) continue;
          const last = tr.pts[tr.pts.length - 1];
          if (f.t - last.t > 0.25) { tr.closed = true; continue; }
          if (f.t === last.t) continue;
          const d = Math.hypot(b.x - last.x, b.y - last.y);
          if (d < bd) { bd = d; best = tr; }
        }
        if (best) best.pts.push({ x: b.x, y: b.y, t: f.t });
        else tracks.push({ pts: [{ x: b.x, y: b.y, t: f.t }], closed: false });
      });
    });
    return tracks.filter((tr) => {
      if (tr.pts.length < CFG.BALL_MIN_TRACK) return false;
      const a = tr.pts[0], z = tr.pts[tr.pts.length - 1];
      const net = Math.hypot(z.x - a.x, z.y - a.y);
      if (net < CFG.BALL_MIN_DISP) return false;

      // Straightness is the discriminator size and persistence could not provide. Sum the
      // step lengths: a ball's path length barely exceeds its net displacement, while
      // wind-jittered foliage wanders far to get nowhere.
      let path = 0;
      for (let i = 1; i < tr.pts.length; i++) path += Math.hypot(tr.pts[i].x - tr.pts[i - 1].x, tr.pts[i].y - tr.pts[i - 1].y);
      if (path <= 0 || net / path < CFG.BALL_MIN_STRAIGHT) return false;

      const dt = z.t - a.t;
      if (dt <= 0 || net / dt < CFG.BALL_MIN_SPEED) return false;   // leaves drift, balls fly
      return true;
    }).map((tr) => ({
      startT: tr.pts[0].t,
      endT: tr.pts[tr.pts.length - 1].t,   // ball arriving ~= the moment worth swinging at
      points: tr.pts.length
    }));
  }

  function diffEnergy(a, b) {
    let acc = 0;
    for (let i = 0; i < a.length; i++) {
      const df = Math.abs(a[i] - b[i]);
      if (df > CFG.MOTION_PIXEL_DELTA) acc += df;
    }
    return acc / a.length;
  }

  // ---------- motion pass ----------
  async function sampleMotion(v, roi, onProgress) {
    const samples = [];
    const ballFrames = [];
    let prev = null, prevBall = null;

    const push = (t) => {
      const g = grayInROI(v, roi);
      const bg = ballGray(v);
      const fresh = t > (samples.length ? samples[samples.length - 1].t : -1);
      if (prev && fresh) samples.push({ t, e: diffEnergy(g, prev) });
      // ball candidates ride along in the same decode pass — a second pass over the video
      // would double the cost of the slowest stage
      if (prevBall && fresh) ballFrames.push({ t, blobs: ballBlobs(bg, prevBall) });
      prev = g; prevBall = bg;
    };
    samples.ballFrames = ballFrames;

    // fast path: playback + rVFC (native cadence, no aliasing)
    const played = await new Promise((res) => {
      if (!('requestVideoFrameCallback' in v)) return res(false);
      let got = 0, settled = false;
      const finish = (ok) => { if (!settled) { settled = true; res(ok); } };
      const onFrame = (now, meta) => {
        push(meta.mediaTime);
        got++;
        if (onProgress && got % 15 === 0) {
          onProgress('Watching the round… ' + Math.round(meta.mediaTime / v.duration * 100) + '%');
        }
        if (!v.paused && !v.ended) v.requestVideoFrameCallback(onFrame);
        else finish(got > 10);
      };
      v.addEventListener('ended', () => finish(got > 10), { once: true });
      v.currentTime = 0;
      v.playbackRate = 4;   // conservative: high rates drop frames on weaker phones
      v.play().then(() => v.requestVideoFrameCallback(onFrame)).catch(() => finish(false));
      // If the renderer is occluded/backgrounded the browser silently refuses to paint —
      // play() resolves but no frames ever arrive. Bail out and seek instead.
      setTimeout(() => { if (got === 0) finish(false); }, 4000);
    });
    if (CFG.DEBUG) console.log('[segment] rVFC path:', played, '| samples:', samples.length);
    if (played) { samples.path = 'rvfc'; return samples; }

    // Second fast path: play + rAF, deduped on currentTime.
    //
    // requestVideoFrameCallback only exists in Safari 15.4+, and without this a slightly
    // older iPhone drops straight to seeking — ~200s for a short clip, which reads as a
    // hang. rAF runs at ~60fps against 30fps video, so consecutive callbacks often land on
    // the same decoded frame; comparing them yields a zero diff and shreds the signal
    // (docs/POSE-PROBE.md #4). Skipping unchanged currentTime gives the same one-sample-per-
    // -frame guarantee rVFC provides, without needing rVFC.
    samples.length = 0; ballFrames.length = 0; prev = null; prevBall = null;
    const rafPlayed = await new Promise((res) => {
      let got = 0, settled = false, lastT = -1;
      const finish = (ok) => { if (!settled) { settled = true; res(ok); } };
      const tick = () => {
        if (settled) return;
        if (v.currentTime !== lastT) { lastT = v.currentTime; push(v.currentTime); got++; }
        if (onProgress && got % 15 === 0 && v.duration) {
          onProgress('Watching the round… ' + Math.round(v.currentTime / v.duration * 100) + '%');
        }
        if (!v.paused && !v.ended) requestAnimationFrame(tick);
        else finish(got > 10);
      };
      v.addEventListener('ended', () => finish(got > 10), { once: true });
      v.currentTime = 0;
      v.playbackRate = 2;   // rAF caps sampling at ~60fps, so don't outrun it
      v.play().then(() => requestAnimationFrame(tick)).catch(() => finish(false));
      setTimeout(() => { if (got === 0) finish(false); }, 4000);
    });
    if (CFG.DEBUG) console.log('[segment] rAF path:', rafPlayed, '| samples:', samples.length);
    if (rafPlayed) { samples.path = 'raf'; return samples; }

    // Last resort: deterministic seeking. Correct but slow (~37ms+/frame) — only reached
    // when the browser refuses to play at all.
    samples.length = 0; ballFrames.length = 0; prev = null; prevBall = null;
    try { v.pause(); } catch (e) { /* fine */ }
    if (onProgress) onProgress('Watching the round…');
    const fps = 15;                      // enough to catch a swing envelope; keeps seeks bounded
    const n = Math.floor(Math.min(v.duration, CFG.CAP_SECONDS * 1.5) * fps);
    for (let i = 0; i < n; i++) {
      const t = i / fps;
      try { await seekTo(v, t); } catch (e) { break; }
      push(t);
      if (onProgress && i % 20 === 0) onProgress('Watching the round… ' + Math.round(i / n * 100) + '%');
    }
    samples.path = 'seek';
    return samples;
  }

  // ---------- audio transients (confirmatory only) ----------
  async function audioPeaks(blobOrUrl) {
    try {
      const buf = blobOrUrl instanceof Blob
        ? await blobOrUrl.arrayBuffer()
        : await (await fetch(blobOrUrl)).arrayBuffer();
      const AC = window.OfflineAudioContext || window.webkitOfflineAudioContext;
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const audio = await ctx.decodeAudioData(buf.slice(0));
      const ch = audio.getChannelData(0);
      const sr = audio.sampleRate;
      const win = Math.floor(sr * 0.01);            // 10ms RMS envelope
      const env = [];
      for (let i = 0; i + win < ch.length; i += win) {
        let s = 0;
        for (let j = 0; j < win; j++) s += ch[i + j] * ch[i + j];
        env.push(Math.sqrt(s / win));
      }
      ctx.close();
      const sorted = [...env].sort((a, b) => a - b);
      const med = sorted[Math.floor(sorted.length / 2)] || 0;
      const hi = sorted[Math.floor(sorted.length * 0.995)] || 0;
      const thr = Math.max(med * 6, hi * 0.45);
      const peaks = [];
      for (let i = 1; i < env.length - 1; i++) {
        if (env[i] > thr && env[i] >= env[i - 1] && env[i] > env[i + 1]) {
          const t = i * 0.01;
          if (!peaks.length || t - peaks[peaks.length - 1] > 0.25) peaks.push(t);
        }
      }
      return peaks;
    } catch (e) {
      return [];   // no audio track, or the container isn't decodable — motion carries it
    }
  }

  // ---------- swing extraction ----------
  function medianSmooth(vals, win) {
    const half = Math.floor(win / 2);
    return vals.map((_, i) => {
      const s = vals.slice(Math.max(0, i - half), i + half + 1).sort((a, b) => a - b);
      return s[Math.floor(s.length / 2)];
    });
  }

  function findSwings(samples, peaks, ballTracks) {
    if (samples.length < 4) return [];
    const raw = samples.map((s) => s.e);
    const sm = medianSmooth(raw, CFG.MOTION_SMOOTH_WIN);
    const sorted = [...sm].sort((a, b) => a - b);
    // baseline = median of the quiet half; a round is mostly waiting, not swinging
    const baseline = sorted[Math.floor(sorted.length * 0.5)] || 0.001;
    const enter = Math.max(baseline * CFG.SPIKE_ENTER_MULT, 0.02);
    const exit = Math.max(baseline * CFG.SPIKE_EXIT_MULT, 0.01);

    // hysteresis: enter high, leave low — a single threshold fragments a noisy signal
    const spans = [];
    let inS = false, st = 0, peakE = 0, peakT = 0;
    for (let i = 0; i < sm.length; i++) {
      const t = samples[i].t;
      if (!inS && sm[i] > enter) { inS = true; st = t; peakE = sm[i]; peakT = t; }
      else if (inS) {
        if (sm[i] > peakE) { peakE = sm[i]; peakT = t; }
        if (sm[i] < exit) { inS = false; spans.push({ start: st, end: t, peakT, peakE }); }
      }
    }
    if (inS) spans.push({ start: st, end: samples[samples.length - 1].t, peakT, peakE });

    // merge spans that are really one swing (load and follow-through can dip between)
    const merged = [];
    for (const s of spans) {
      const last = merged[merged.length - 1];
      if (last && s.start - last.end < CFG.MIN_GAP_SEC) {
        last.end = s.end;
        if (s.peakE > last.peakE) { last.peakE = s.peakE; last.peakT = s.peakT; }
      } else merged.push(Object.assign({}, s));
    }

    const tracks = ballTracks || [];
    return merged
      .filter((s) => s.end - s.start >= CFG.MIN_SWING_SEC)
      // THE GATE: a motion spike is only a swing if a ball arrived around it. Bringing the
      // bat back to the shoulder moves plenty; no ball ever shows up for it.
      .filter((s) => {
        if (!tracks.length) return true;   // no ball track anywhere: fall back to motion
        return tracks.some((tr) => Math.abs(tr.endT - s.peakT) <= CFG.BALL_NEAR_SEC ||
          (s.start - CFG.BALL_NEAR_SEC <= tr.endT && tr.endT <= s.end + CFG.BALL_NEAR_SEC));
      })
      .map((s) => {
        // audio only sharpens contact; its absence never disqualifies a swing (whiffs count)
        const near = peaks.filter((p) => Math.abs(p - s.peakT) <= CFG.AUDIO_CONFIRM_SEC);
        const contactT = near.length
          ? near.reduce((a, b) => (Math.abs(b - s.peakT) < Math.abs(a - s.peakT) ? b : a))
          : s.peakT;
        return {
          start: Math.max(0, s.start - CFG.PRE_PAD_SEC),
          end: s.end + CFG.POST_PAD_SEC,
          contactT,
          audioConfirmed: near.length > 0,
          confidence: s.peakE / Math.max(baseline, 0.001)
        };
      });
  }

  // ---------- keyframes ----------
  // The raw upload is released after segmentation and never persisted, so anything the
  // film room, Chalk or Deep Dive will ever need must be extracted now.
  async function extractKeyframes(v, swing, onProgress) {
    const out = [];
    const n = CFG.KEYFRAMES_PER_SWING;
    const scale = Math.min(1, CFG.KEYFRAME_WIDTH / v.videoWidth);
    kcv.width = Math.round(v.videoWidth * scale);
    kcv.height = Math.round(v.videoHeight * scale);
    const end = Math.min(swing.end, v.duration);
    for (let i = 0; i < n; i++) {
      const t = swing.start + (end - swing.start) * (i / (n - 1));
      try { await seekTo(v, t); } catch (e) { break; }
      kctx.drawImage(v, 0, 0, kcv.width, kcv.height);
      const blob = await new Promise((r) => kcv.toBlob(r, 'image/jpeg', CFG.KEYFRAME_QUALITY));
      if (blob) out.push({ t, blob });
      if (onProgress) onProgress();
    }
    return out;
  }

  // ---------- public ----------
  // Returns { swings:[{start,end,contactT,frames,...}], capHit, durationSec, meta }
  // opts.video: a element already primed by primeVideo() inside the user's tap. Passing one
  // is what keeps iOS on the fast path; without it this still works, just slower.
  async function segment(fileOrBlob, opts) {
    const onProgress = (opts && opts.onProgress) || function () {};
    const primed = opts && opts.video;
    const url = primed ? primed._objectUrl : URL.createObjectURL(fileOrBlob);
    let v = null;
    try {
      onProgress('Opening the round…');
      v = primed ? await ready(primed) : await loadVideo(url);
      const durationSec = v.duration || 0;

      const roi = null;   // full-frame: see the note above grayInROI()
      const [samples, peaks] = [await sampleMotion(v, roi, onProgress), await audioPeaks(fileOrBlob)];
      if (CFG.DEBUG) console.log('[segment] samples', samples.length, 'audio peaks', peaks.length);

      let ballTracks = linkBallTracks(samples.ballFrames || []);
      if (CFG.DEBUG) console.log('[segment] ball tracks:', ballTracks.length, ballTracks.slice(0, 12).map((t) => t.startT.toFixed(2) + '->' + t.endT.toFixed(2)));
      // If we're finding a ball everywhere, we are finding noise — and a gate that matches
      // everything is worse than no gate, because it looks like it worked.
      if (ballTracks.length > CFG.BALL_MAX_TRACKS) {
        if (CFG.DEBUG) console.warn('[segment] ball detector saturated (' + ballTracks.length + ') — ignoring it');
        ballTracks = [];
      }
      let swings = findSwings(samples, peaks, ballTracks);

      // ---- caps: 90s OR 15 swings, whichever comes first ----
      let capHit = null;
      if (durationSec > CFG.CAP_SECONDS) {
        const before = swings.length;
        swings = swings.filter((s) => s.start < CFG.CAP_SECONDS);
        swings.forEach((s) => { s.end = Math.min(s.end, CFG.CAP_SECONDS); });
        if (swings.length < before || durationSec > CFG.CAP_SECONDS) capHit = 'time';
      }
      if (swings.length > CFG.CAP_SWINGS) {
        swings = swings.slice(0, CFG.CAP_SWINGS);
        capHit = 'swings';
      }

      // ---- keyframes ----
      const totalFrames = swings.length * CFG.KEYFRAMES_PER_SWING;
      let done = 0;
      for (let i = 0; i < swings.length; i++) {
        swings[i].frames = await extractKeyframes(v, swings[i], () => {
          done++;
          onProgress('Cutting swing ' + (i + 1) + ' of ' + swings.length + '… ' + Math.round(done / totalFrames * 100) + '%');
        });
      }

      return {
        swings, capHit, durationSec,
        meta: {
          sampleCount: samples.length, audioPeaks: peaks.length, usedAudio: peaks.length > 0,
          primed: !!primed, path: samples.path || 'none', ballTracks: ballTracks.length,
          rvfc: ('requestVideoFrameCallback' in v), ua: navigator.userAgent.slice(0, 80)
        }
      };
    } finally {
      // release the raw upload: never persisted, gone as soon as we have the cuts
      if (v) releaseVideo(v);
      URL.revokeObjectURL(url);
    }
  }

  window.DugoutSegment = { segment, primeVideo, loadVideo, releaseVideo, seekTo, findSwings, audioPeaks };
})();
