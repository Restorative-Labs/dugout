// Dugout — app shell: routing, the round pipeline, and every view except the film room.
(function () {
  const CFG = window.DUGOUT_CONFIG;
  const Store = window.DugoutStore;
  const Seg = window.DugoutSegment;
  const Ev = window.DugoutEvaluate;
  const AI = window.DugoutAI;
  const L = window.DUGOUT_LIBRARY;

  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const el = (tag, cls, txt) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt !== undefined) e.textContent = txt;
    return e;
  };
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const urls = new Set();
  const objURL = (blob) => { const u = URL.createObjectURL(blob); urls.add(u); return u; };
  const dropURLs = () => { urls.forEach((u) => URL.revokeObjectURL(u)); urls.clear(); };

  // ---------------- routing ----------------
  const VIEWS = ['home', 'capture', 'round', 'progress', 'philosophy', 'film'];
  let route = { name: 'home', arg: null };

  function go(name, arg) {
    location.hash = '#/' + name + (arg ? '/' + arg : '');
  }

  function readHash() {
    const m = (location.hash || '#/home').replace(/^#\//, '').split('/');
    const name = VIEWS.indexOf(m[0]) >= 0 ? m[0] : 'home';
    return { name, arg: m[1] || null };
  }

  function render() {
    route = readHash();
    VIEWS.forEach((v) => {
      const node = $('#view-' + v);
      if (node) node.hidden = v !== route.name;
    });
    $('#navFilm').classList.toggle('on', route.name === 'film');
    $('#navHome').classList.toggle('on', route.name === 'home');
    window.scrollTo(0, 0);
    if (route.name === 'home') renderHome();
    if (route.name === 'round') renderRound(route.arg);
    if (route.name === 'progress') renderProgress();
    if (route.name === 'philosophy') renderPhilosophy();
  }
  window.addEventListener('hashchange', render);

  // ---------------- profiles ----------------
  function activeProfile() {
    const id = Store.lastProfileId();
    return (id && Store.profile(id)) || Store.profiles()[0] || null;
  }

  function renderProfileChip() {
    const p = activeProfile();
    const chip = $('#profileChip');
    if (!p) { chip.hidden = true; return; }
    chip.hidden = false;
    chip.textContent = p.name + ' · ' + CFG.AGE_BAND_LABEL[p.ageBand];
  }

  function renderHome() {
    renderProfileChip();
    const profiles = Store.profiles();
    const wrap = $('#profileList');
    wrap.innerHTML = '';

    profiles.forEach((p) => {
      const row = el('button', 'profile-row' + (activeProfile() && p.id === activeProfile().id ? ' on' : ''));
      row.innerHTML = '<span class="pname">' + esc(p.name) + '</span>' +
        '<span class="pband">' + CFG.AGE_BAND_LABEL[p.ageBand] + '</span>' +
        '<span class="pcount">' + Store.sessions(p.id).length + ' rounds</span>';
      row.onclick = () => { Store.setLastProfile(p.id); renderHome(); };
      wrap.appendChild(row);
    });

    $('#addProfile').hidden = profiles.length >= CFG.MAX_PROFILES;
    $('#noProfile').hidden = profiles.length > 0;
    $('#roundActions').hidden = profiles.length === 0;

    // recent rounds for the active profile
    const p = activeProfile();
    const recent = $('#recentRounds');
    recent.innerHTML = '';
    if (p) {
      const sessions = Store.sessions(p.id).slice(0, 5);
      $('#recentWrap').hidden = sessions.length === 0;
      sessions.forEach((s) => {
        const passes = s.evaluation ? CFG.CHECKPOINTS.filter((c) => s.evaluation[c] && s.evaluation[c].pass).length : 0;
        const row = el('button', 'round-row');
        row.innerHTML = '<span class="rdate">' + new Date(s.startedAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) + '</span>' +
          '<span class="rswings">' + (s.swings || []).length + ' swings</span>' +
          '<span class="rmarks">' + passes + '/6 ✓</span>';
        row.onclick = () => go('round', s.id);
        recent.appendChild(row);
      });
    } else {
      $('#recentWrap').hidden = true;
    }
  }

  $('#addProfile').onclick = () => { $('#profileForm').hidden = false; $('#pfName').focus(); };
  $('#pfCancel').onclick = () => { $('#profileForm').hidden = true; };
  $('#pfSave').onclick = () => {
    const name = $('#pfName').value.trim();
    if (!name) { $('#pfName').focus(); return; }
    const band = $('#pfBand').value;
    try {
      Store.addProfile(name, band);
      $('#pfName').value = '';
      $('#profileForm').hidden = true;
      renderHome();
    } catch (e) {
      $('#pfErr').textContent = e.message;
    }
  };

  // ---------------- capture: the round pipeline ----------------
  const setStatus = (msg) => { $('#capStatus').textContent = msg; };
  const setBar = (pct) => { $('#capBar').style.width = Math.max(0, Math.min(100, pct)) + '%'; };

  async function runRound(fileOrBlob, source) {
    const profile = activeProfile();
    if (!profile) { go('home'); return; }

    go('capture');
    $('#capTitle').textContent = 'Reading the round';
    $('#capErr').hidden = true;
    $('#capDone').hidden = true;
    setBar(4);

    try {
      // ---- segment ----
      const t0 = performance.now();
      const result = await Seg.segment(fileOrBlob, {
        onProgress: (m) => {
          setStatus(m);
          const pct = /(\d+)%/.exec(m);
          if (pct) setBar(4 + parseInt(pct[1], 10) * 0.5);
        }
      });

      if (!result.swings.length) {
        throw new Error('No swings found in that clip. Film from the side with his whole body in frame, and make sure the swing is actually in the video.');
      }

      // ---- evaluate each swing (no AI, no user selection) ----
      const session = Store.newSession(profile.id, source, 'home');
      session.durationSec = result.durationSec;
      session.capHit = result.capHit;

      const philosophy = Store.activePhilosophy();
      const swingResults = [];
      const totalPose = result.swings.length * CFG.POSE_SAMPLES_PER_SWING;
      let posed = 0;

      for (let i = 0; i < result.swings.length; i++) {
        const sw = result.swings[i];
        const swingId = Store.uid('swg');
        setStatus('Reading swing ' + (i + 1) + ' of ' + result.swings.length + '…');

        const r = await Ev.analyzeSwing(sw.frames, sw.contactT, () => {
          posed++;
          setBar(54 + (posed / totalPose) * 42);
        });
        r.swingId = swingId;
        swingResults.push(r);

        await Store.putFrames(swingId, sw.frames.map((f) => ({ t: f.t, blob: f.blob })));
        session.swings.push({
          id: swingId, sessionId: session.id, index: i,
          start: sw.start, end: sw.end, contactT: sw.contactT,
          audioConfirmed: sw.audioConfirmed, confidence: sw.confidence,
          grade: null, notes: '', poseOk: r.ok
        });
      }

      // ---- rollup ----
      setStatus('Grading the six checkpoints…');
      setBar(97);
      const perCheckpoint = Ev.rollup(swingResults, profile, philosophy);
      const focus = Ev.priorityFocus(perCheckpoint, philosophy);
      const feedback = Ev.composeFeedback(perCheckpoint, focus, profile, philosophy);

      // per-swing grade: terse, from how many faults that swing showed
      session.swings.forEach((s, i) => {
        const r = swingResults[i];
        if (!r.ok) { s.grade = '—'; return; }
        const hits = Object.values(r.faults).filter((f) => f.conf >= Ev.FAULT_PRESENT).length;
        s.grade = hits === 0 ? 'Clean' : hits === 1 ? 'Close' : 'Work';
      });

      // best swing = fewest faults, tie-break on detector confidence
      let best = null, bestScore = 1e9;
      swingResults.forEach((r, i) => {
        if (!r.ok) return;
        const score = Object.values(r.faults).reduce((a, f) => a + f.conf, 0);
        if (score < bestScore) { bestScore = score; best = session.swings[i].id; }
      });
      session.bestSwingId = best;

      // ---- one AI call for the session, or the deterministic library composition ----
      const rendered = await AI.sessionFeedback({
        feedback, profile, philosophy, perCheckpoint, swingCount: session.swings.length
      });

      session.evaluation = perCheckpoint;
      session.priorityFocus = focus;
      session.feedback = {
        headline: rendered.text.headline,
        body: rendered.text.body,
        cue: rendered.text.cue,
        cueTipId: feedback.cue && feedback.tipIdsUsed[0] ? feedback.tipIdsUsed[0] : null,
        drills: feedback.drills,
        tipIdsUsed: feedback.tipIdsUsed,
        celebrate: feedback.celebrate,
        source: rendered.source
      };
      session.meta = Object.assign({}, result.meta, { elapsedMs: Math.round(performance.now() - t0) });

      Store.saveSession(session);
      setBar(100);
      go('round', session.id);
    } catch (e) {
      console.error(e);
      $('#capErr').hidden = false;
      $('#capErr').textContent = e.message || 'Something went wrong reading that round.';
      setStatus('');
    }
  }

  // upload entry points
  $('#btnRound').onclick = () => $('#fileRound').click();
  $('#fileRound').addEventListener('change', (e) => {
    const f = e.target.files[0];
    if (f) runRound(f, 'upload');
    e.target.value = '';
  });
  $('#btnSingle').onclick = () => $('#fileSingle').click();
  $('#fileSingle').addEventListener('change', (e) => {
    const f = e.target.files[0];
    if (f) runRound(f, 'upload');   // a single clip is just a session of one
    e.target.value = '';
  });
  $('#capBack').onclick = () => go('home');

  // ---------------- DUG-35: timed in-app round ----------------
  let rec = null, recStream = null, recChunks = [], recTimer = null, recStop = null;

  $('#btnRecord').onclick = () => { $('#recSheet').hidden = false; };
  $('#recCancel').onclick = () => { $('#recSheet').hidden = true; };
  $$('.rec-preset').forEach((b) => {
    b.onclick = () => {
      $$('.rec-preset').forEach((x) => x.classList.remove('on'));
      b.classList.add('on');
    };
  });

  $('#recStart').onclick = async () => {
    const secs = parseInt(($('.rec-preset.on') || $$('.rec-preset')[1]).dataset.secs, 10);
    $('#recSheet').hidden = true;
    go('capture');
    $('#capTitle').textContent = 'Recording';
    $('#capErr').hidden = true;
    $('#recLive').hidden = false;
    setStatus('');

    try {
      recStream = await navigator.mediaDevices.getUserMedia({
        // bound resolution/bitrate: a 90s window at full res will fill a phone
        video: { facingMode: 'environment', width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } },
        audio: true
      });
    } catch (e) {
      $('#recLive').hidden = true;
      $('#capErr').hidden = false;
      $('#capErr').textContent = 'Dugout needs camera access to record a round. You can still upload a video instead.';
      return;
    }

    const prev = $('#recPreview');
    prev.srcObject = recStream;
    prev.muted = true;
    await prev.play().catch(() => {});

    recChunks = [];
    const mime = ['video/mp4', 'video/webm;codecs=vp9', 'video/webm'].find((m) => MediaRecorder.isTypeSupported(m)) || '';
    rec = new MediaRecorder(recStream, mime ? { mimeType: mime, videoBitsPerSecond: 4000000 } : {});
    rec.ondataavailable = (e) => { if (e.data && e.data.size) recChunks.push(e.data); };

    const finish = (why) => {
      if (recStop) return;
      recStop = why;
      clearInterval(recTimer);
      try { rec.stop(); } catch (e) { /* already stopped */ }
    };

    rec.onstop = async () => {
      recStream.getTracks().forEach((t) => t.stop());
      prev.srcObject = null;
      $('#recLive').hidden = true;
      const blob = new Blob(recChunks, { type: rec.mimeType || 'video/webm' });
      recChunks = [];
      if (blob.size < 1000) {
        $('#capErr').hidden = false;
        $('#capErr').textContent = 'That recording came out empty. Try again.';
        return;
      }
      await runRound(blob, 'live');
    };

    // Interruption recovery: a screen lock or a phone call pauses the page. Whatever was
    // captured up to that point is still a valid round, so stop cleanly and use it.
    const onHide = () => { if (document.hidden) finish('interrupted'); };
    document.addEventListener('visibilitychange', onHide, { once: true });

    rec.start(1000);   // timeslice: chunks land every second so an interruption keeps them
    let left = secs;
    $('#recCount').textContent = left;
    recTimer = setInterval(() => {
      left--;
      $('#recCount').textContent = left;
      if (left <= 0) finish('time');
    }, 1000);

    // live swing counter -> auto-stop at the swing cap
    liveSwingWatch(prev, () => finish('swings'));
    $('#recStopNow').onclick = () => finish('manual');
  };

  // Lightweight live detection: same motion-energy idea as segmentation, just enough to
  // know when 15 swings have happened. The real segmentation still runs afterwards.
  function liveSwingWatch(video, onCap) {
    const c = document.createElement('canvas');
    c.width = CFG.MOTION_W; c.height = CFG.MOTION_H;
    const x = c.getContext('2d', { willReadFrequently: true });
    let prev = null, count = 0, hot = false, baseline = null, quiet = [];
    $('#recSwings').textContent = '0';

    const tick = () => {
      if (recStop) return;
      try { x.drawImage(video, 0, 0, c.width, c.height); } catch (e) { return requestAnimationFrame(tick); }
      const d = x.getImageData(0, 0, c.width, c.height).data;
      const g = new Float32Array(c.width * c.height);
      for (let i = 0, p = 0; i < d.length; i += 4, p++) g[p] = d[i] * 0.299 + d[i + 1] * 0.587 + d[i + 2] * 0.114;
      if (prev) {
        let acc = 0;
        for (let p = 0; p < g.length; p++) { const df = Math.abs(g[p] - prev[p]); if (df > CFG.MOTION_PIXEL_DELTA) acc += df; }
        const e = acc / g.length;
        quiet.push(e);
        if (quiet.length > 90) quiet.shift();
        if (quiet.length >= 30) {
          const s = [...quiet].sort((a, b) => a - b);
          baseline = s[Math.floor(s.length / 2)] || 0.01;
          if (!hot && e > Math.max(baseline * CFG.SPIKE_ENTER_MULT, 0.02)) {
            hot = true; count++;
            $('#recSwings').textContent = String(count);
            if (count >= CFG.CAP_SWINGS) return onCap();
          } else if (hot && e < Math.max(baseline * CFG.SPIKE_EXIT_MULT, 0.01)) hot = false;
        }
      }
      prev = g;
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  // ---------------- Round Card ----------------
  async function renderRound(id) {
    const s = Store.session(id);
    if (!s) { go('home'); return; }
    dropURLs();
    const profile = Store.profile(s.profileId);
    const fb = s.feedback || {};

    $('#rcDate').textContent = new Date(s.startedAt).toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' });
    $('#rcWho').textContent = (profile ? profile.name : '') + ' · ' + (s.swings || []).length + ' swings';

    // cap message — friendly, never a scold
    const cap = $('#rcCap');
    if (s.capHit === 'swings') {
      cap.hidden = false;
      cap.textContent = 'That’s a full round! We analyzed the first ' + CFG.CAP_SWINGS + ' swings.';
    } else if (s.capHit === 'time') {
      cap.hidden = false;
      cap.textContent = 'That’s a full round! We analyzed the first ' + CFG.CAP_SECONDS + ' seconds.';
    } else cap.hidden = true;

    // ---- verbal first: the correction is the headline ----
    $('#rcCelebrate').hidden = !fb.celebrate;
    $('#rcHeadline').textContent = fb.headline || '';
    $('#rcBody').textContent = fb.body || '';
    const cueWrap = $('#rcCueWrap');
    if (fb.cue) {
      cueWrap.hidden = false;
      $('#rcCue').textContent = '“' + fb.cue + '”';
    } else cueWrap.hidden = true;

    // ---- drills sit BELOW the verbal correction, as recommendations ----
    const dw = $('#rcDrills');
    dw.innerHTML = '';
    (fb.drills || []).forEach((d) => {
      const li = el('li', null, d.name);
      dw.appendChild(li);
    });
    $('#rcDrillWrap').hidden = !(fb.drills || []).length;

    // ---- six checkpoints: pass/fail only, no numbers anywhere ----
    const marks = $('#rcMarks');
    marks.innerHTML = '';
    CFG.CHECKPOINTS.forEach((cp) => {
      const e = (s.evaluation || {})[cp] || { pass: true, assessed: false };
      const isFocus = s.priorityFocus === cp;
      const card = el('div', 'mark' + (e.pass ? ' pass' : ' fail') + (isFocus ? ' focus' : '') + (e.assessed ? '' : ' na'));
      card.innerHTML =
        '<span class="mk">' + (!e.assessed ? '·' : e.pass ? '✓' : '✗') + '</span>' +
        '<span class="mlabel">' + CFG.CHECKPOINT_LABEL[cp] + '</span>' +
        (isFocus ? '<span class="mfocus">work on this</span>' : '') +
        (!e.assessed ? '<span class="mna">not assessed</span>' : '');
      marks.appendChild(card);
    });

    // ---- swing reel ----
    const reel = $('#rcReel');
    reel.innerHTML = '';
    for (const sw of (s.swings || [])) {
      const frames = await Store.getFrames(sw.id);
      const thumbBlob = frames && frames.length ? frames[Math.floor(frames.length * CFG.CONTACT_ANCHOR)].blob : null;
      const b = el('button', 'swing' + (sw.id === s.bestSwingId ? ' best' : ''));
      b.innerHTML =
        (thumbBlob ? '<img src="' + objURL(thumbBlob) + '" alt="Swing ' + (sw.index + 1) + '">' : '<div class="noimg"></div>') +
        '<span class="sidx">' + (sw.index + 1) + '</span>' +
        '<span class="sgrade">' + esc(sw.grade || '') + '</span>' +
        (sw.id === s.bestSwingId ? '<span class="sbest">★ best</span>' : '');
      b.onclick = () => openSwing(s.id, sw.id);
      reel.appendChild(b);
    }

    $('#rcCorrect').onclick = () => openSlangEditor(s);
    $('#rcSource').textContent = fb.source === 'ai' ? '' : 'Composed from the tip library';
  }

  // ---- corrections loop: voice only, never substance ----
  function openSlangEditor(session) {
    const tipId = (session.feedback && session.feedback.tipIdsUsed && session.feedback.tipIdsUsed[0]) || null;
    if (!tipId) return;
    const phi = Store.activePhilosophy();
    $('#slangSheet').hidden = false;
    $('#slangCurrent').textContent = '“' + (session.feedback.cue || '') + '”';
    $('#slangInput').value = (phi.slang && phi.slang[tipId]) || '';
    $('#slangErr').hidden = true;
    $('#slangSave').onclick = () => {
      const v = $('#slangInput').value.trim();
      if (!v) return;
      if (Ev.isDeprecated(v)) {
        $('#slangErr').hidden = false;
        $('#slangErr').textContent = 'That phrase is one Dugout leaves out on purpose — it teaches the opposite of what the swing needs. Try it another way.';
        return;
      }
      // materialise a custom card so edits never mutate the suggested baseline
      let card = phi.source === 'suggested' ? Store.newPhilosophy('My Philosophy', phi.preset) : phi;
      card.slang = Object.assign({}, card.slang, {});
      card.slang[tipId] = v;
      card.active = true;
      Store.savePhilosophy(card);
      Store.setActivePhilosophy(card.id);
      session.feedback.cue = v;
      Store.saveSession(session);
      $('#slangSheet').hidden = true;
      renderRound(session.id);
    };
    $('#slangCancel').onclick = () => { $('#slangSheet').hidden = true; };
  }

  // ---- open one swing in the film room (Chalk available) ----
  async function openSwing(sessionId, swingId) {
    const frames = await Store.getFrames(swingId);
    if (!frames || !frames.length) return;
    window.DugoutFilm.loadFrames(frames.map((f) => ({ t: f.t, url: objURL(f.blob) })), {
      sessionId, swingId,
      onDeepDive: () => deepDive(sessionId, swingId)
    });
    go('film');
  }

  // ---- Deep Dive: the v1 8-frame single-swing analysis, on demand ----
  async function deepDive(sessionId, swingId) {
    const s = Store.session(sessionId);
    const profile = s && Store.profile(s.profileId);
    const frames = await Store.getFrames(swingId);
    if (!frames) return;
    const n = 8;
    const picks = [];
    for (let i = 0; i < n; i++) picks.push(frames[Math.round(i * (frames.length - 1) / (n - 1))]);
    return window.DugoutFilm.deepDive(picks, profile);
  }

  // ---------------- progress (DUG-36) ----------------
  // Streaks and trend arrows only — no numeric scales, per spec.
  function renderProgress() {
    const p = activeProfile();
    $('#pgWho').textContent = p ? p.name : '';
    const sessions = p ? Store.sessions(p.id).filter((s) => s.evaluation).reverse() : [];   // oldest first
    $('#pgEmpty').hidden = sessions.length >= 2;
    $('#pgBody').hidden = sessions.length < 2;
    if (sessions.length < 2) return;

    const wrap = $('#pgList');
    wrap.innerHTML = '';
    CFG.CHECKPOINTS.forEach((cp) => {
      const marks = sessions.map((s) => s.evaluation[cp] && s.evaluation[cp].assessed ? !!s.evaluation[cp].pass : null);
      const known = marks.filter((m) => m !== null);
      // current streak of passes, counting back from the latest round
      let streak = 0;
      for (let i = marks.length - 1; i >= 0; i--) {
        if (marks[i] === true) streak++;
        else if (marks[i] === false) break;
      }
      const half = Math.floor(known.length / 2);
      const early = known.slice(0, half).filter(Boolean).length / Math.max(1, half);
      const late = known.slice(half).filter(Boolean).length / Math.max(1, known.length - half);
      const trend = late - early > 0.15 ? '▲' : early - late > 0.15 ? '▼' : '▬';

      const row = el('div', 'pg-row');
      row.innerHTML =
        '<span class="pglabel">' + CFG.CHECKPOINT_LABEL[cp] + '</span>' +
        '<span class="pgline">' + marks.map((m) =>
          '<i class="' + (m === null ? 'na' : m ? 'ok' : 'no') + '">' + (m === null ? '·' : m ? '✓' : '✗') + '</i>').join('') + '</span>' +
        '<span class="pgtrend ' + (trend === '▲' ? 'up' : trend === '▼' ? 'down' : 'flat') + '">' + trend + '</span>';
      const note = el('div', 'pgnote');
      note.textContent = streak >= 2
        ? CFG.CHECKPOINT_LABEL[cp] + ': passed ' + streak + ' straight rounds' + (streak >= 3 ? ' 🔥' : '')
        : '';
      wrap.appendChild(row);
      if (note.textContent) wrap.appendChild(note);
    });
  }

  // ---------------- philosophy (DUG-36) ----------------
  // Selection, not authoring: pick a preset, adjust tips, order priorities, mark red lines,
  // add your own words. Mostly tapping.
  let draft = null;

  function renderPhilosophy() {
    const active = Store.activePhilosophy();
    draft = draft || JSON.parse(JSON.stringify(active));

    // presets
    const pw = $('#phPresets');
    pw.innerHTML = '';
    const presets = [{ preset: 'DugOut Suggested', notes: 'The library’s own baseline ranking. A good place to start.' }].concat(L.schools);
    presets.forEach((s) => {
      const b = el('button', 'preset' + (draft.preset === s.preset ? ' on' : ''));
      b.innerHTML = '<b>' + esc(s.preset) + '</b><small>' + esc((s.beliefs || s.notes || '').slice(0, 96)) + '</small>';
      b.onclick = () => {
        draft.preset = s.preset;
        draft.name = s.preset === 'DugOut Suggested' ? 'DugOut Suggested' : 'My Philosophy';
        if (s.emphasisIds && s.emphasisIds.length) {
          // seed selections from the school's emphases, but never drop a checkpoint entirely
          const sel = {};
          CFG.CHECKPOINTS.forEach((cp) => {
            const ids = L.tips.filter((t) => t.checkpoint === cp && s.emphasisIds.indexOf(t.id) >= 0).map((t) => t.id);
            if (ids.length) sel[cp] = ids;
          });
          draft.tipSelections = sel;
        } else draft.tipSelections = {};
        renderPhilosophy();
      };
      pw.appendChild(b);
    });

    // tips per checkpoint
    const tw = $('#phTips');
    tw.innerHTML = '';
    CFG.CHECKPOINTS.forEach((cp) => {
      const sec = el('div', 'ph-cp');
      sec.appendChild(el('h4', null, CFG.CHECKPOINT_LABEL[cp]));
      L.tips.filter((t) => t.checkpoint === cp).forEach((t) => {
        const on = !draft.tipSelections[cp] || !draft.tipSelections[cp].length || draft.tipSelections[cp].indexOf(t.id) >= 0;
        const red = draft.redLineTipIds.indexOf(t.id) >= 0;
        const row = el('div', 'ph-tip' + (red ? ' red' : ''));
        row.innerHTML =
          '<label><input type="checkbox" ' + (on && !red ? 'checked' : '') + ' ' + (red ? 'disabled' : '') + '>' +
          '<span class="tf">' + esc(t.fault) + '</span></label>' +
          '<span class="tmeta">' + (t.detector ? '' : '<span class="tgap" title="Needs ball or bat tracking — not assessed offline">◐</span>') +
          '<span class="ttier t' + t.tier + '">' + t.tier + '</span></span>' +
          '<button class="tred" title="Red line: never use this tip">' + (red ? 'red-lined' : 'red line') + '</button>';
        $('input', row).onchange = (e) => {
          const cur = draft.tipSelections[cp] || L.tips.filter((x) => x.checkpoint === cp).map((x) => x.id);
          draft.tipSelections[cp] = e.target.checked ? cur.concat([t.id]).filter((v, i, a) => a.indexOf(v) === i) : cur.filter((x) => x !== t.id);
        };
        $('.tred', row).onclick = () => {
          const i = draft.redLineTipIds.indexOf(t.id);
          if (i >= 0) draft.redLineTipIds.splice(i, 1); else draft.redLineTipIds.push(t.id);
          renderPhilosophy();
        };
        sec.appendChild(row);
      });
      tw.appendChild(sec);
    });

    // priority order
    const ow = $('#phOrder');
    ow.innerHTML = '';
    (draft.priorities.length ? draft.priorities : CFG.CHECKPOINTS).forEach((cp, i) => {
      const row = el('div', 'ph-ord');
      row.innerHTML = '<span class="on">' + (i + 1) + '</span><span class="ol">' + CFG.CHECKPOINT_LABEL[cp] + '</span>';
      const up = el('button', 'mini', '↑'); const dn = el('button', 'mini', '↓');
      up.onclick = () => { if (i > 0) { const a = draft.priorities; [a[i - 1], a[i]] = [a[i], a[i - 1]]; renderPhilosophy(); } };
      dn.onclick = () => { const a = draft.priorities; if (i < a.length - 1) { [a[i + 1], a[i]] = [a[i], a[i + 1]]; renderPhilosophy(); } };
      row.appendChild(up); row.appendChild(dn);
      ow.appendChild(row);
    });

    // slang for selected tips
    const sw = $('#phSlang');
    sw.innerHTML = '';
    const selectedTips = L.tips.filter((t) =>
      draft.redLineTipIds.indexOf(t.id) < 0 &&
      (!draft.tipSelections[t.checkpoint] || !draft.tipSelections[t.checkpoint].length || draft.tipSelections[t.checkpoint].indexOf(t.id) >= 0) &&
      t.cues.length);
    selectedTips.slice(0, 12).forEach((t) => {
      const row = el('div', 'ph-slang');
      row.innerHTML = '<div class="sl-base">' + esc(t.cues[0]) + '</div>';
      const inp = el('input');
      inp.placeholder = 'What do YOU say for this?';
      inp.value = (draft.slang && draft.slang[t.id]) || '';
      inp.oninput = () => { draft.slang[t.id] = inp.value.trim(); if (!inp.value.trim()) delete draft.slang[t.id]; };
      row.appendChild(inp);
      sw.appendChild(row);
    });

    $('#phDeprecated').innerHTML = L.cueGlossary.filter((g) => g.status === 'deprecated')
      .map((g) => '<li><b>' + esc(g.phrases.join('” / “')) + '</b> — ' + esc(g.why.split(';')[0]) + '</li>').join('');
  }

  $('#phSave').onclick = () => {
    const card = draft.source === 'suggested' && draft.preset === 'DugOut Suggested' && !Object.keys(draft.slang).length && !draft.redLineTipIds.length
      ? Store.suggestedPhilosophy()
      : Object.assign(Store.newPhilosophy(draft.name || 'My Philosophy', draft.preset), {
          id: draft.id && draft.id !== 'dugout-suggested' ? draft.id : undefined,
          tipSelections: draft.tipSelections, priorities: draft.priorities,
          redLineTipIds: draft.redLineTipIds, slang: draft.slang, source: 'custom'
        });
    if (!card.id) card.id = Store.uid('phi');
    card.active = true;
    Store.savePhilosophy(card);
    Store.setActivePhilosophy(card.id);
    $('#phSaved').classList.add('show');
    setTimeout(() => $('#phSaved').classList.remove('show'), 1800);
  };
  $('#phReset').onclick = () => { draft = JSON.parse(JSON.stringify(Store.suggestedPhilosophy())); renderPhilosophy(); };

  // ---------------- boot ----------------
  $('#navHome').onclick = (e) => { e.preventDefault(); go('home'); };
  $('#navFilm').onclick = (e) => { e.preventDefault(); go('film'); };
  $('#navProgress').onclick = (e) => { e.preventDefault(); go('progress'); };
  $('#navPhilosophy').onclick = (e) => { e.preventDefault(); go('philosophy'); };

  render();
  window.DugoutApp = { go, activeProfile, runRound, render };
})();
