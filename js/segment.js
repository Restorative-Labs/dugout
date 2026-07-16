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

  function loadVideo(src) {
    return new Promise((res, rej) => {
      const v = document.createElement('video');
      v.src = src; v.muted = true; v.playsInline = true; v.preload = 'auto';
      // Chrome will not decode or paint a detached <video>; it must be in the document.
      v.style.cssText = 'position:fixed;left:-9999px;top:0;width:160px;pointer-events:none;opacity:0.01';
      document.body.appendChild(v);
      v.addEventListener('loadedmetadata', () => res(v), { once: true });
      v.addEventListener('error', () => rej(new Error('That video could not be read. Try a different clip.')), { once: true });
      setTimeout(() => rej(new Error('That video took too long to open.')), 30000);
    });
  }

  const releaseVideo = (v) => {
    try { v.pause(); } catch (e) { /* already gone */ }
    v.removeAttribute('src');
    v.load();
    if (v.parentNode) v.parentNode.removeChild(v);
  };

  // ---------- batter ROI ----------
  // Spec asks for differencing "in the batter region". We don't know it up front, so
  // sample a few frames, pose them, and take a padded union. Falls back to the full frame.
  // This matters on real footage: wind-moving trees and a fence are otherwise pure noise.
  async function batterROI(v, onProgress) {
    try {
      if (onProgress) onProgress('Finding the hitter…');
      const boxes = [];
      const dur = v.duration || 1;
      for (const f of [0.25, 0.5, 0.75]) {
        try {
          await seekTo(v, dur * f);
          const p = await window.DugoutPose.estimate(v, CFG.MOTION_W * 4, CFG.MOTION_H * 4);
          const bb = p && window.DugoutPose.bbox(p);
          if (bb) boxes.push(bb);
        } catch (e) { /* this sample failed; others may not */ }
      }
      if (!boxes.length) return null;
      const u = {
        x0: Math.min(...boxes.map((b) => b.x0)), x1: Math.max(...boxes.map((b) => b.x1)),
        y0: Math.min(...boxes.map((b) => b.y0)), y1: Math.max(...boxes.map((b) => b.y1))
      };
      // generous pad: he drifts between pitches, and the bat swings well outside his joints
      const W = CFG.MOTION_W * 4, H = CFG.MOTION_H * 4;
      const padX = (u.x1 - u.x0) * 0.9, padY = (u.y1 - u.y0) * 0.35;
      return {
        x0: Math.max(0, (u.x0 - padX) / W), x1: Math.min(1, (u.x1 + padX) / W),
        y0: Math.max(0, (u.y0 - padY) / H), y1: Math.min(1, (u.y1 + padY) / H)
      };
    } catch (e) {
      return null;
    }
  }

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
    let prev = null;

    const push = (t) => {
      const g = grayInROI(v, roi);
      if (prev && t > (samples.length ? samples[samples.length - 1].t : -1)) {
        samples.push({ t, e: diffEnergy(g, prev) });
      }
      prev = g;
    };

    // fast path: playback + rVFC (native cadence, no aliasing)
    const played = await new Promise((res) => {
      if (!('requestVideoFrameCallback' in v)) return res(false);
      let got = 0, settled = false;
      const finish = (ok) => { if (!settled) { settled = true; res(ok); } };
      const onFrame = (now, meta) => {
        push(meta.mediaTime);
        got++;
        if (onProgress && got % 30 === 0) {
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

    if (played) return samples;

    // fallback: deterministic seeking. Slower, but works when playback is refused.
    samples.length = 0; prev = null;
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

  function findSwings(samples, peaks) {
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

    return merged
      .filter((s) => s.end - s.start >= CFG.MIN_SWING_SEC)
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
  async function segment(fileOrBlob, opts) {
    const onProgress = (opts && opts.onProgress) || function () {};
    const url = URL.createObjectURL(fileOrBlob);
    let v = null;
    try {
      onProgress('Opening the round…');
      v = await loadVideo(url);
      const durationSec = v.duration || 0;

      await window.DugoutPose.load(onProgress);
      const roi = await batterROI(v, onProgress);

      const [samples, peaks] = [await sampleMotion(v, roi, onProgress), await audioPeaks(fileOrBlob)];
      if (CFG.DEBUG) console.log('[segment] samples', samples.length, 'audio peaks', peaks.length, 'roi', roi);

      let swings = findSwings(samples, peaks);

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
        meta: { sampleCount: samples.length, audioPeaks: peaks.length, roi, usedAudio: peaks.length > 0 }
      };
    } finally {
      // release the raw upload: never persisted, gone as soon as we have the cuts
      if (v) releaseVideo(v);
      URL.revokeObjectURL(url);
    }
  }

  window.DugoutSegment = { segment, loadVideo, releaseVideo, seekTo, findSwings, audioPeaks };
})();
