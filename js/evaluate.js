// Dugout — six-checkpoint evaluation (DUG-34).
//
// Per swing: sample a pose track, measure the faults the library defines, and score each
// checkpoint. Per session: roll up across swings, pass/fail against PASS_THRESHOLDS, pick
// one priority focus, and render it verbal-first in the active philosophy's vocabulary.
//
// Honesty rules baked in:
//   - Faults whose library entry has `detector: null` are NEVER guessed at. A checkpoint is
//     scored only on what can actually be measured (docs/POSE-PROBE.md).
//   - ER-03: a fault seen in one swing is never named.
//   - Internal scores are never displayed.
//
// A note on viewing angle: the app asks for a side view, where rotation about the vertical
// axis appears as the *projected width* of the hip/shoulder line changing sign and
// magnitude, not as an in-image angle. So rotation is tracked via signed projected
// separation, which is stable from the side. Depth-axis faults (stepping in the bucket) are
// weak from this angle and are scored with deliberately low confidence.
(function () {
  const CFG = window.DUGOUT_CONFIG;
  const P = window.DugoutPose;

  const clamp01 = (v) => Math.max(0, Math.min(1, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  // 0 below lo, 1 above hi — turns a raw measurement into a fault confidence
  const ramp = (v, lo, hi) => clamp01((v - lo) / (hi - lo || 1));

  // ---------- pose track ----------
  async function buildTrack(frames, onProgress) {
    const step = Math.max(1, Math.floor(frames.length / CFG.POSE_SAMPLES_PER_SWING));
    const track = [];
    for (let i = 0; i < frames.length; i += step) {
      const f = frames[i];
      const bmp = await createImageBitmap(f.blob);
      try {
        const pose = await P.estimate(bmp, bmp.width, bmp.height);
        if (pose) track.push({ t: f.t, u: 0, pose, w: bmp.width, h: bmp.height });
      } finally {
        bmp.close();
      }
      if (onProgress) onProgress();
    }
    if (!track.length) return null;
    const t0 = track[0].t, t1 = track[track.length - 1].t;
    track.forEach((s) => { s.u = t1 > t0 ? (s.t - t0) / (t1 - t0) : 0; });
    return track;
  }

  // ---------- derived per-frame geometry ----------
  function geom(s) {
    const g = (n) => P.ok(s.pose, n);
    const ls = g('left_shoulder'), rs = g('right_shoulder');
    const lh = g('left_hip'), rh = g('right_hip');
    const la = g('left_ankle'), ra = g('right_ankle');
    const lw = g('left_wrist'), rw = g('right_wrist');
    const le = g('left_elbow'), re = g('right_elbow');
    const lk = g('left_knee'), rk = g('right_knee');
    const nose = g('nose');
    const shoMid = P.mid(ls, rs), hipMid = P.mid(lh, rh), ankMid = P.mid(la, ra);
    // scale everything by torso length so thresholds are camera-distance invariant
    const scale = shoMid && hipMid ? Math.max(1, P.dist(shoMid, hipMid)) : null;
    return {
      ls, rs, lh, rh, la, ra, lw, rw, le, re, lk, rk, nose,
      shoMid, hipMid, ankMid, scale,
      // signed projected separation: the side-view-stable rotation proxy
      hipSep: lh && rh ? (rh.x - lh.x) : null,
      shoSep: ls && rs ? (rs.x - ls.x) : null,
      wristMid: P.mid(lw, rw)
    };
  }

  // Which way is the pitcher? The front foot strides toward them, so the ankle that
  // displaces most horizontally over the swing gives both the direction and which foot
  // is which — no handedness setting required from the parent.
  function orient(track) {
    const first = geom(track[0]), last = geom(track[track.length - 1]);
    const mids = track.map(geom).filter((g) => g.la && g.ra);
    if (!mids.length || !first.scale) return null;
    const a0 = mids[0], aN = mids[Math.floor(mids.length * 0.7)] || mids[mids.length - 1];
    const dL = aN.la.x - a0.la.x, dR = aN.ra.x - a0.ra.x;
    const frontIsLeft = Math.abs(dL) >= Math.abs(dR);
    const d = frontIsLeft ? dL : dR;
    if (Math.abs(d) < 1) return { dir: 1, frontIsLeft, weak: true };
    return { dir: Math.sign(d), frontIsLeft, weak: false };
  }

  const at = (track, u) => {
    let best = track[0], bd = 1e9;
    track.forEach((s) => { const d = Math.abs(s.u - u); if (d < bd) { bd = d; best = s; } });
    return best;
  };
  const between = (track, u0, u1) => track.filter((s) => s.u >= u0 && s.u <= u1);

  function series(track, pick) {
    return track.map((s) => ({ u: s.u, t: s.t, v: pick(geom(s)) })).filter((p) => p.v !== null && p.v !== undefined && !isNaN(p.v));
  }

  function maxDeriv(sig) {
    let best = { rate: 0, t: null, u: null };
    for (let i = 1; i < sig.length; i++) {
      const dt = sig[i].t - sig[i - 1].t;
      if (dt <= 0) continue;
      const r = Math.abs(sig[i].v - sig[i - 1].v) / dt;
      if (r > best.rate) best = { rate: r, t: sig[i].t, u: sig[i].u };
    }
    return best;
  }

  // ---------- detectors ----------
  // Each returns { conf } where conf is fault confidence 0..1, or null if unmeasurable
  // on this swing (missing joints). Never fabricates.
  const DETECTORS = {
    'stance.baseWidth': (ctx) => {
      const g = geom(at(ctx.track, 0.05));
      if (!g.la || !g.ra || !g.ls || !g.rs) return null;
      const ank = Math.abs(g.ra.x - g.la.x), sho = Math.abs(g.rs.x - g.ls.x);
      if (sho < 1) return null;
      const ratio = ank / sho;
      // ~1.0-1.9x shoulder width is the athletic band; fault ramps either side
      const conf = ratio < 1.0 ? ramp(1.0 - ratio, 0.05, 0.5) : ramp(ratio - 1.9, 0.05, 0.8);
      return { conf, detail: 'base/shoulder ' + ratio.toFixed(2) };
    },

    'stance.weightBias': (ctx) => {
      const g = geom(at(ctx.track, 0.05));
      if (!g.hipMid || !g.la || !g.ra || !g.scale) return null;
      const back = ctx.o.dir > 0 ? Math.min(g.la.x, g.ra.x) : Math.max(g.la.x, g.ra.x);
      const front = ctx.o.dir > 0 ? Math.max(g.la.x, g.ra.x) : Math.min(g.la.x, g.ra.x);
      const span = front - back;
      if (Math.abs(span) < 1) return null;
      // 0 = fully back, 1 = fully forward. Want ~0.4 (60/40 rear favour).
      const pos = (g.hipMid.x - back) / span;
      const conf = ramp(pos - 0.5, 0.02, 0.35);
      return { conf, detail: 'weight pos ' + pos.toFixed(2) };
    },

    'load.noLoad': (ctx) => {
      const seg = between(ctx.track, CFG.PHASE_WINDOWS.load[0], CFG.PHASE_WINDOWS.load[1]).map(geom);
      if (seg.length < 2 || !ctx.scale) return null;
      const hips = seg.filter((g) => g.hipMid);
      if (hips.length < 2) return null;
      const travel = Math.max(...hips.map((g) => g.hipMid.x)) - Math.min(...hips.map((g) => g.hipMid.x));
      const norm = travel / ctx.scale;
      // no gather at all = the hips never move back before launch
      return { conf: 1 - ramp(norm, 0.02, 0.14), detail: 'load travel ' + norm.toFixed(3) };
    },

    'load.drift': (ctx) => {
      const a = geom(at(ctx.track, 0.08)), b = geom(at(ctx.track, CFG.CONTACT_ANCHOR));
      const h0 = a.nose || a.shoMid, h1 = b.nose || b.shoMid;
      if (!h0 || !h1 || !ctx.scale) return null;
      // head travelling toward the pitcher = lunging
      const drift = (h1.x - h0.x) * ctx.o.dir / ctx.scale;
      return { conf: ramp(drift, 0.12, 0.55), detail: 'head drift ' + drift.toFixed(3) };
    },

    'stride.overstride': (ctx) => {
      const s0 = geom(at(ctx.track, 0.05)), s1 = geom(at(ctx.track, CFG.CONTACT_ANCHOR));
      if (!s0.la || !s0.ra || !s1.la || !s1.ra || !ctx.scale) return null;
      const base = Math.abs(s0.ra.x - s0.la.x), land = Math.abs(s1.ra.x - s1.la.x);
      if (base < 1) return null;
      const growth = land / base;
      const spanNorm = land / ctx.scale;
      // both a big jump from the base AND an absolute span too wide to rotate from
      return { conf: Math.max(ramp(growth, 1.7, 2.6), ramp(spanNorm, 2.1, 3.2)), detail: 'stride growth ' + growth.toFixed(2) };
    },

    'stride.bucket': (ctx) => {
      // Weak from a side view — the bucket step is mostly along the camera axis. Scored
      // conservatively and capped so it can never become a priority focus on its own.
      const s0 = geom(at(ctx.track, 0.05)), s1 = geom(at(ctx.track, CFG.CONTACT_ANCHOR));
      const f0 = ctx.o.frontIsLeft ? s0.la : s0.ra;
      const f1 = ctx.o.frontIsLeft ? s1.la : s1.ra;
      if (!f0 || !f1 || !ctx.scale) return null;
      const lateral = Math.abs(f1.y - f0.y) / ctx.scale;
      return { conf: Math.min(0.55, ramp(lateral, 0.25, 0.8)), detail: 'front-foot lateral ' + lateral.toFixed(3), lowConfidence: true };
    },

    'stride.headMove': (ctx) => {
      const seg = between(ctx.track, 0.05, CFG.CONTACT_ANCHOR).map(geom).filter((g) => g.nose || g.shoMid);
      if (seg.length < 3 || !ctx.scale) return null;
      const pts = seg.map((g) => g.nose || g.shoMid);
      const dx = Math.max(...pts.map((p) => p.x)) - Math.min(...pts.map((p) => p.x));
      const dy = Math.max(...pts.map((p) => p.y)) - Math.min(...pts.map((p) => p.y));
      const move = Math.hypot(dx, dy) / ctx.scale;
      return { conf: ramp(move, 0.25, 0.85), detail: 'head travel ' + move.toFixed(3) };
    },

    // Timing, from pelvis rotation peak vs the contact frame (audio-sharpened when available).
    'stride.early': (ctx) => {
      if (!ctx.rotPeak || ctx.contactU === null) return null;
      const lead = ctx.contactU - ctx.rotPeak.u;   // rotation finished this far before contact
      return { conf: ramp(lead, 0.10, 0.30), detail: 'rotation lead ' + lead.toFixed(3) };
    },

    'stride.late': (ctx) => {
      if (!ctx.rotPeak || ctx.contactU === null) return null;
      const lag = ctx.rotPeak.u - ctx.contactU;    // still accelerating at/after contact
      return { conf: ramp(lag, 0.04, 0.22), detail: 'rotation lag ' + lag.toFixed(3) };
    },

    'hips.rotationSpeed': (ctx) => {
      if (!ctx.rotPeak || !ctx.scale) return null;
      const norm = ctx.rotPeak.rate / ctx.scale;   // torso-lengths per second
      return { conf: 1 - ramp(norm, 1.2, 5.0), detail: 'hip rot ' + norm.toFixed(2) + '/s' };
    },

    'hips.separation': (ctx) => {
      if (!ctx.rotPeak || !ctx.shoPeak) return null;
      // hips should lead the shoulders; near-zero lag = rotating as one block
      const lag = ctx.shoPeak.u - ctx.rotPeak.u;
      return { conf: 1 - ramp(lag, 0.005, 0.09), detail: 'hip→shoulder lag ' + lag.toFixed(3) };
    },

    'hips.flyOpen': (ctx) => {
      if (!ctx.rotPeak || !ctx.shoPeak) return null;
      // shoulders beating the hips open is the fault
      const lead = ctx.rotPeak.u - ctx.shoPeak.u;
      return { conf: ramp(lead, 0.01, 0.14), detail: 'shoulder lead ' + lead.toFixed(3) };
    },

    'hips.backsideCollapse': (ctx) => {
      const g = geom(at(ctx.track, CFG.CONTACT_ANCHOR));
      const s = geom(at(ctx.track, 0.05));
      if (!g.shoMid || !g.hipMid || !s.shoMid || !s.hipMid || !ctx.scale) return null;
      // spine tilting away from the pitcher + posture dropping
      const tilt0 = (s.shoMid.x - s.hipMid.x) * ctx.o.dir / ctx.scale;
      const tilt1 = (g.shoMid.x - g.hipMid.x) * ctx.o.dir / ctx.scale;
      const drop = (g.hipMid.y - s.hipMid.y) / ctx.scale;
      return { conf: Math.max(ramp(tilt0 - tilt1, 0.18, 0.6), ramp(drop, 0.12, 0.45)), detail: 'tilt Δ' + (tilt0 - tilt1).toFixed(2) + ' drop ' + drop.toFixed(2) };
    },

    'contact.casting': (ctx) => {
      // rear elbow gets outside the hands early in the turn (Hemond's detection rule)
      const u = lerp(CFG.PHASE_WINDOWS.hips[0], CFG.CONTACT_ANCHOR, 0.4);
      const g = geom(at(ctx.track, u));
      const elbow = ctx.o.frontIsLeft ? g.re : g.le;
      const wrist = ctx.o.frontIsLeft ? g.rw : g.lw;
      if (!elbow || !wrist || !ctx.scale) return null;
      const outside = (wrist.x - elbow.x) * ctx.o.dir / ctx.scale;
      // hands should lead the elbow toward the pitcher; elbow outside = casting
      return { conf: 1 - ramp(outside, -0.05, 0.35), detail: 'hands-ahead ' + outside.toFixed(3) };
    },

    'contact.batDrag': (ctx) => {
      // rear elbow in front of the hands during the turn
      const u = lerp(CFG.PHASE_WINDOWS.hips[0], CFG.CONTACT_ANCHOR, 0.7);
      const g = geom(at(ctx.track, u));
      const elbow = ctx.o.frontIsLeft ? g.re : g.le;
      const wrist = ctx.o.frontIsLeft ? g.rw : g.lw;
      if (!elbow || !wrist || !ctx.scale) return null;
      const ahead = (elbow.x - wrist.x) * ctx.o.dir / ctx.scale;
      return { conf: ramp(ahead, 0.05, 0.4), detail: 'elbow-ahead ' + ahead.toFixed(3) };
    },

    'contact.headPull': (ctx) => {
      const g0 = geom(at(ctx.track, lerp(CFG.PHASE_WINDOWS.stride[0], CFG.CONTACT_ANCHOR, 0.5)));
      const g1 = geom(at(ctx.track, CFG.CONTACT_ANCHOR));
      if (!g0.nose || !g1.nose || !g0.shoMid || !g1.shoMid || !ctx.scale) return null;
      // face rotating toward the pull side before contact = eyes leaving the ball
      const rel0 = (g0.nose.x - g0.shoMid.x) * ctx.o.dir / ctx.scale;
      const rel1 = (g1.nose.x - g1.shoMid.x) * ctx.o.dir / ctx.scale;
      return { conf: ramp(rel0 - rel1, 0.1, 0.5), detail: 'head turn ' + (rel0 - rel1).toFixed(3) };
    },

    'finish.balance': (ctx) => {
      const seg = between(ctx.track, CFG.PHASE_WINDOWS.finish[0], 1).map(geom).filter((g) => g.ankMid && g.hipMid);
      if (seg.length < 2 || !ctx.scale) return null;
      // hips travelling over the base after the swing, or the feet resettling = a recovery step
      const hipSway = Math.max(...seg.map((g) => Math.abs(g.hipMid.x - g.ankMid.x))) / ctx.scale;
      const footShift = (Math.max(...seg.map((g) => g.ankMid.x)) - Math.min(...seg.map((g) => g.ankMid.x))) / ctx.scale;
      return { conf: Math.max(ramp(hipSway, 0.55, 1.4), ramp(footShift, 0.2, 0.7)), detail: 'sway ' + hipSway.toFixed(2) + ' step ' + footShift.toFixed(2) };
    },

    'finish.height': (ctx) => {
      const seg = between(ctx.track, CFG.PHASE_WINDOWS.finish[0], 1).map(geom).filter((g) => g.wristMid && g.shoMid);
      if (!seg.length || !ctx.scale) return null;
      // hands proxy for the barrel: a chop finish leaves them at or below the waist
      const best = Math.min(...seg.map((g) => g.wristMid.y - g.shoMid.y)) / ctx.scale;
      return { conf: ramp(best, 0.15, 0.85), detail: 'hands vs shoulder ' + best.toFixed(2) };
    }
  };

  // ---------- per-swing ----------
  async function analyzeSwing(frames, contactT, onProgress) {
    const track = await buildTrack(frames, onProgress);
    if (!track || track.length < 4) return { ok: false, reason: 'no-pose', faults: {} };

    const o = orient(track);
    if (!o) return { ok: false, reason: 'no-orientation', faults: {} };

    const scales = track.map(geom).map((g) => g.scale).filter(Boolean);
    const scale = scales.length ? scales.sort((a, b) => a - b)[Math.floor(scales.length / 2)] : null;
    if (!scale) return { ok: false, reason: 'no-scale', faults: {} };

    const hipSig = series(track, (g) => g.hipSep);
    const shoSig = series(track, (g) => g.shoSep);
    const rotPeak = hipSig.length > 2 ? maxDeriv(hipSig) : null;
    const shoPeak = shoSig.length > 2 ? maxDeriv(shoSig) : null;

    const t0 = track[0].t, t1 = track[track.length - 1].t;
    const contactU = (contactT !== null && contactT !== undefined && t1 > t0)
      ? clamp01((contactT - t0) / (t1 - t0)) : CFG.CONTACT_ANCHOR;

    const ctx = { track, o, scale, rotPeak, shoPeak, contactU };

    const faults = {};
    window.DUGOUT_LIBRARY.tips.forEach((tip) => {
      if (!tip.detector || tip.isToggle) return;      // never guessed at
      const fn = DETECTORS[tip.detector];
      if (!fn) return;
      let r = null;
      try { r = fn(ctx); } catch (e) { r = null; }
      if (r && typeof r.conf === 'number' && !isNaN(r.conf)) {
        faults[tip.id] = { conf: clamp01(r.conf), detail: r.detail, lowConfidence: !!r.lowConfidence };
        if (CFG.DEBUG) console.log('[detect]', tip.id, r.conf.toFixed(2), r.detail);
      }
    });

    return { ok: true, faults, orientation: o, contactU, trackLength: track.length };
  }

  // ---------- session rollup ----------
  const FAULT_PRESENT = 0.5;   // a detector above this is calling the fault on that swing

  function rollup(swingResults, profile, philosophy) {
    const good = swingResults.filter((s) => s.ok);
    const n = good.length;
    const perCheckpoint = {};
    const band = profile ? profile.ageBand : '11-13';

    CFG.CHECKPOINTS.forEach((cp) => {
      const tips = window.DUGOUT_LIBRARY.tips.filter((t) =>
        t.checkpoint === cp && t.detector && !t.isToggle &&
        t.ageBands.indexOf(band) >= 0 &&
        philosophy.redLineTipIds.indexOf(t.id) < 0 &&
        selected(philosophy, cp, t.id));

      const faultIds = [];
      const evidence = {};
      let cleanliness = [];

      tips.forEach((tip) => {
        const seen = good.filter((s) => s.faults[tip.id]);
        if (!seen.length) return;
        const hits = seen.filter((s) => s.faults[tip.id].conf >= FAULT_PRESENT);
        // ER-03: never name a fault from a single swing
        const enough = hits.length >= CFG.MIN_FAULT_SWINGS || (n > 0 && hits.length / n >= CFG.MIN_FAULT_SHARE && hits.length >= 2);
        if (hits.length && enough) {
          faultIds.push(tip.id);
          evidence[tip.id] = hits.map((s) => s.swingId);
        }
        // score contribution: share of swings clean of this fault, weighted by confidence
        const cleanShare = seen.reduce((a, s) => a + (1 - s.faults[tip.id].conf), 0) / seen.length;
        cleanliness.push(cleanShare);
      });

      const internalScore = cleanliness.length
        ? cleanliness.reduce((a, b) => a + b, 0) / cleanliness.length
        : null;   // nothing measurable for this checkpoint on this round

      const thr = CFG.PASS_THRESHOLDS[cp] || CFG.PASS_THRESHOLD_DEFAULT;
      perCheckpoint[cp] = {
        pass: internalScore === null ? true : internalScore >= thr,
        assessed: internalScore !== null,
        internalScore,          // never rendered
        faultIds,
        evidenceSwingIds: Object.values(evidence).flat().filter((v, i, a) => a.indexOf(v) === i)
      };
    });

    return perCheckpoint;
  }

  const selected = (phi, cp, tipId) => {
    const sel = phi.tipSelections && phi.tipSelections[cp];
    return !sel || !sel.length || sel.indexOf(tipId) >= 0;
  };

  // Lowest-scoring failing checkpoint; ties break on the philosophy's priority order.
  function priorityFocus(perCheckpoint, philosophy) {
    const fails = CFG.CHECKPOINTS.filter((cp) => perCheckpoint[cp].assessed && !perCheckpoint[cp].pass);
    if (!fails.length) return null;
    const order = philosophy.priorities && philosophy.priorities.length ? philosophy.priorities : CFG.CHECKPOINTS;
    fails.sort((a, b) => {
      const d = perCheckpoint[a].internalScore - perCheckpoint[b].internalScore;
      if (Math.abs(d) > 0.02) return d;
      return order.indexOf(a) - order.indexOf(b);
    });
    return fails[0];
  }

  // ---------- feedback rendering ----------
  const tipById = (id) => window.DUGOUT_LIBRARY.tips.find((t) => t.id === id);

  function isDeprecated(text) {
    const low = (text || '').toLowerCase();
    return window.DUGOUT_LIBRARY.deprecatedCues.some((p) => low.indexOf(p) >= 0);
  }

  // Voice only: slang never changes which tip or what substance is delivered.
  function renderCue(tip, philosophy, band) {
    const slang = philosophy.slang && philosophy.slang[tip.id];
    if (slang && !isDeprecated(slang)) return { text: slang, source: 'slang' };
    const baseline = (tip.cues || []).find((c) => !isDeprecated(c));
    if (baseline) return { text: baseline, source: 'library' };
    return { text: tip.tip, source: 'tip' };
  }

  // ER-05 + ER-10 + ER-07
  function drillsFor(tip, band) {
    let ds = tip.drills.slice();
    if (CFG.WEIGHTED_IMPLEMENT_BANDS.indexOf(band) < 0) ds = ds.filter((d) => !d.weighted);
    // prescribe at the lowest rung available — tee/front toss are staples, not remedial
    ds.sort((a, b) => CFG.DRILL_RUNGS.indexOf(a.rung) - CFG.DRILL_RUNGS.indexOf(b.rung));
    return ds.slice(0, 2);
  }

  function composeFeedback(perCheckpoint, focus, profile, philosophy) {
    const band = profile ? profile.ageBand : '11-13';
    const funFirst = CFG.FUN_FIRST_BANDS.indexOf(band) >= 0;

    if (!focus) {
      const strong = CFG.CHECKPOINTS.filter((cp) => perCheckpoint[cp].assessed && perCheckpoint[cp].pass);
      const name = strong.length ? CFG.CHECKPOINT_LABEL[strong[0]] : 'the whole swing';
      return {
        headline: 'All six checkpoints — clean round.',
        body: 'Nothing to fix today. ' + name + ' looked especially good, so make that the thing he keeps.',
        cue: null, drills: [], tipIdsUsed: [], celebrate: true
      };
    }

    const cpFaults = perCheckpoint[focus].faultIds.map(tipById).filter(Boolean);
    if (!cpFaults.length) {
      return {
        headline: CFG.CHECKPOINT_LABEL[focus] + ' is the next thing to work on.',
        body: 'The pattern is there across the round, but no single fault stood out clearly enough to name.',
        cue: null, drills: [], tipIdsUsed: [], celebrate: false
      };
    }

    const tip = cpFaults[0];
    const cue = renderCue(tip, philosophy, band);
    const drills = drillsFor(tip, band);

    return {
      headline: funFirst
        ? 'Next up: ' + CFG.CHECKPOINT_LABEL[focus].toLowerCase() + '.'
        : CFG.CHECKPOINT_LABEL[focus] + ' — ' + tip.fault.toLowerCase(),
      // ER-05: 7-10 gets the outcome and the game, not mechanical surgery
      body: funFirst ? tip.cues[0] || tip.tip : tip.tip,
      cue, drills, tipIdsUsed: cpFaults.map((t) => t.id), celebrate: false
    };
  }

  window.DugoutEvaluate = {
    analyzeSwing, rollup, priorityFocus, composeFeedback, renderCue, drillsFor,
    isDeprecated, tipById, DETECTORS, FAULT_PRESENT
  };
})();
