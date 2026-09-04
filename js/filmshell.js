// Dugout — film space v2 chrome (DUG-40): overlay icon rail, slide-up panels,
// Perfect Swing flag + compare, AI visibility gating.
//
// filmroom.js keeps owning playback/chalk/compare/AI mechanics (it binds by id and
// none of its ids moved). This file only owns the NEW shell around it.
(function () {
  const CFG = window.DUGOUT_CONFIG;
  const Store = window.DugoutStore;
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

  // ---------------- panels ----------------
  const DRAWERS = ['panel-chalk'];                 // compact, no backdrop, stage stays usable
  const SHEETS = ['panel-learn', 'panel-compare', 'panel-ai', 'panel-notes'];
  let openId = null;

  function setRailState() {
    $$('.fr-btn[data-fpanel]').forEach((b) => b.classList.toggle('on', b.dataset.fpanel === openId));
  }

  function openPanel(id) {
    if (openId === id) return closeAll();
    closeAll(true);
    openId = id;
    const node = $('#' + id);
    node.hidden = false;
    if (SHEETS.indexOf(id) >= 0) $('#filmBackdrop').hidden = false;
    requestAnimationFrame(() => {
      node.classList.add('show');
      if (SHEETS.indexOf(id) >= 0) $('#filmBackdrop').classList.add('show');
    });
    if (id === 'panel-compare') renderPSCompare();
    setRailState();
  }

  function closeAll(immediate) {
    const was = openId;
    openId = null;
    DRAWERS.concat(SHEETS).forEach((id) => {
      const node = $('#' + id);
      if (!node || node.hidden) return;
      node.classList.remove('show');
      if (immediate) node.hidden = true;
      else setTimeout(() => { node.hidden = true; }, 300);
    });
    const back = $('#filmBackdrop');
    if (back && !back.hidden) {
      back.classList.remove('show');
      if (immediate) back.hidden = true;
      else setTimeout(() => { back.hidden = true; }, 300);
    }
    setRailState();
    return was;
  }

  $$('.fr-btn[data-fpanel]').forEach((b) => { b.onclick = () => openPanel(b.dataset.fpanel); });
  $$('#view-film [data-fclose]').forEach((b) => { b.onclick = () => closeAll(); });
  $('#filmBackdrop').onclick = () => closeAll();

  // ---------------- AI visibility (DUG-40 R6) ----------------
  function applyAI() {
    const on = window.DugoutAI.hasKey();
    $('#railAI').hidden = !on;
    if (!on && openId === 'panel-ai') closeAll(true);
  }

  // ---------------- Perfect Swing (DUG-40 R5) ----------------
  let current = null;   // {sessionId, swingId, profileId} when a stored swing is open

  function perfectOf(profileId) {
    const p = Store.profile(profileId);
    return (p && p.perfectSwing) || null;
  }

  function setStarState() {
    const star = $('#railStar');
    if (!current) { star.hidden = true; return; }
    star.hidden = false;
    const ps = perfectOf(current.profileId);
    star.classList.toggle('set', !!(ps && ps.swingId === current.swingId));
  }

  $('#railStar').onclick = () => {
    if (!current) return;
    const p = Store.profile(current.profileId);
    if (!p) return;
    const already = p.perfectSwing && p.perfectSwing.swingId === current.swingId;
    if (already) return flashStar('Already his Perfect Swing ★');
    const history = (p.perfectSwingHistory || []).concat(p.perfectSwing ? [p.perfectSwing] : []);
    Store.updateProfile(p.id, {
      perfectSwing: { swingId: current.swingId, sessionId: current.sessionId, setAt: Date.now() },
      perfectSwingHistory: history.slice(-10)
    });
    setStarState();
    flashStar('★ Perfect Swing set — Compare now measures against it');
  };

  let toastTimer = null;
  function flashStar(msg) {
    let t = $('#filmToast');
    if (!t) {
      t = el('div', 'filmtoast');
      t.id = 'filmToast';
      $('#view-film .fstage-wrap').appendChild(t);
    }
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), 2200);
  }

  // ---------------- Perfect Swing compare renderer ----------------
  // Two frame sequences stepped together: the swing on screen vs the flagged one.
  let cmp = null;   // {a:[urls], b:[urls], i, offB}
  const urls = [];
  const objURL = (blob) => { const u = URL.createObjectURL(blob); urls.push(u); return u; };

  async function renderPSCompare() {
    const box = $('#psCompare');
    box.innerHTML = '';
    cmp = null;
    urls.splice(0).forEach((u) => URL.revokeObjectURL(u));

    const profile = window.DugoutApp.activeProfile();
    const ps = current ? perfectOf(current.profileId) : (profile && profile.perfectSwing) || null;

    if (!ps) {
      box.appendChild(el('p', 'hint',
        'No Perfect Swing yet. Open any swing from a Round Card and tap the ★ Perfect button — from then on, Compare measures him against his own best.'));
      return;
    }
    if (!current) {
      box.appendChild(el('p', 'hint',
        'Open a swing from a Round Card first, then Compare shows it side-by-side with his Perfect Swing.'));
      return;
    }

    const [curFrames, psFrames] = await Promise.all([
      Store.getFrames(current.swingId), Store.getFrames(ps.swingId)
    ]);
    if (!psFrames || !psFrames.length) {
      box.appendChild(el('p', 'hint',
        'His Perfect Swing’s film is gone (that round was deleted). Star a new one and Compare comes back.'));
      return;
    }
    if (!curFrames || !curFrames.length) return;

    cmp = {
      a: curFrames.map((f) => objURL(f.blob)),
      b: psFrames.map((f) => objURL(f.blob)),
      i: 0, offB: 0
    };

    const same = current.swingId === ps.swingId;
    const grid = el('div', 'ps-grid');
    grid.innerHTML =
      '<div class="ps-cell"><span class="clabel">This swing</span><img id="psA" alt="This swing"></div>' +
      '<div class="ps-cell"><span class="clabel">★ Perfect Swing</span><img id="psB" alt="Perfect Swing"></div>';
    box.appendChild(grid);
    if (same) box.appendChild(el('p', 'hint', 'This IS his Perfect Swing — open another swing to measure against it.'));

    const ctl = el('div', 'ps-ctl');
    ctl.innerHTML =
      '<button class="mini" id="psPrev">‹ frame</button>' +
      '<span class="timecode" id="psTc">1</span>' +
      '<button class="mini" id="psNext">frame ›</button>' +
      '<span class="spacer"></span>' +
      '<span class="ps-nudge">align ★ <button class="mini" id="psNb">‹</button><button class="mini" id="psNf">›</button></span>';
    box.appendChild(ctl);
    box.appendChild(el('p', 'hint',
      'Step both a frame at a time. Use align to slide the Perfect Swing until both are at the same moment — front-foot touchdown is the easiest landmark.'));

    const draw = () => {
      const a = cmp.a, b = cmp.b;
      cmp.i = Math.max(0, Math.min(a.length - 1, cmp.i));
      const bi = Math.max(0, Math.min(b.length - 1, cmp.i + cmp.offB));
      $('#psA').src = a[cmp.i];
      $('#psB').src = b[bi];
      $('#psTc').textContent = (cmp.i + 1) + '/' + a.length;
    };
    $('#psPrev').onclick = () => { cmp.i--; draw(); };
    $('#psNext').onclick = () => { cmp.i++; draw(); };
    $('#psNb').onclick = () => { cmp.offB--; draw(); };
    $('#psNf').onclick = () => { cmp.offB++; draw(); };
    draw();
  }

  // ---------------- DUG-42: per-swing indicators + contextual Learn ----------------
  const Ev = () => window.DugoutEvaluate;
  const Lb = () => window.DUGOUT_LIBRARY;

  // Which checkpoints are flagged for the round, and for THIS swing specifically.
  function swingContext(session, swingId) {
    const swing = (session.swings || []).find((s) => s.id === swingId);
    const out = { round: {}, swing: {}, count: 0 };
    CFG.CHECKPOINTS.forEach((cp) => {
      const e = (session.evaluation || {})[cp];
      const roundFail = !!(e && e.assessed && !e.pass);
      out.round[cp] = e ? (e.assessed ? (e.pass ? 'pass' : 'fail') : 'na') : 'na';
      let thisSwing = false;
      if (roundFail && swing) {
        if (swing.faultIds && swing.faultIds.length) {
          thisSwing = swing.faultIds.some((id) => {
            const t = Ev().tipById(id);
            return t && t.checkpoint === cp;
          });
        } else {
          // pre-DUG-42 sessions: fall back to round evidence
          thisSwing = (e.evidenceSwingIds || []).indexOf(swing.id) >= 0 || true;
        }
      }
      out.swing[cp] = thisSwing;
      if (roundFail) out.count++;
    });
    return out;
  }

  function renderIndicators(session, swingId) {
    let strip = $('#swingDots');
    if (!strip) {
      strip = el('div', 'swingdots');
      strip.id = 'swingDots';
      strip.onclick = () => openPanel('panel-learn');
      $('#view-film .fstage-wrap').appendChild(strip);
    }
    const ctx = swingContext(session, swingId);
    strip.innerHTML = CFG.CHECKPOINTS.map((cp) => {
      const st = ctx.round[cp];
      const hot = ctx.swing[cp];
      return '<span class="sd ' + st + (hot ? ' hot' : '') + '">' +
        '<i>' + (st === 'pass' ? '✓' : st === 'fail' ? '✗' : '·') + '</i>' +
        esc(CFG.CHECKPOINT_LABEL[cp]) + '</span>';
    }).join('');
    strip.hidden = false;

    // Learn rail lights up with the number of sections carrying a coach's tip
    setLearnBadge(ctx.count);
    injectCoachTips(session);
  }

  function setLearnBadge(n) {
    const learn = $('.fr-btn[data-fpanel="panel-learn"]');
    let b = learn.querySelector('.badge');
    if (!n) { if (b) b.remove(); learn.classList.remove('noti'); return; }
    if (!b) { b = el('span', 'badge'); learn.appendChild(b); }
    b.textContent = n;
    learn.classList.add('noti');
  }

  // Inside Learn: flag the failed sections and put the coach's tip for this round at the
  // top of each — fault → fix → cue (in the active correction rules' words) → drills.
  function injectCoachTips(session) {
    const panel = $('#panel-learn');
    $$('.coachtip', panel).forEach((n) => n.remove());
    $$('.cp', panel).forEach((d) => d.classList.remove('cp-flag'));
    if (!session) return;
    const phi = Store.activePhilosophy();
    const profile = Store.profile(session.profileId);
    const band = profile ? profile.ageBand : '11-13';
    const details = $$('.cp', panel);

    CFG.CHECKPOINTS.forEach((cp, i) => {
      const e = (session.evaluation || {})[cp];
      if (!e || !e.assessed || e.pass || !details[i]) return;
      details[i].classList.add('cp-flag');
      const tips = (e.faultIds || []).map(Ev().tipById).filter(Boolean);
      const box = el('div', 'coachtip');
      box.innerHTML = '<b>Coach’s tip · from this round</b>' + (tips.length ? tips.map((tip) => {
        const cue = Ev().renderCue(tip, phi, band);
        const drills = Ev().drillsFor(tip, band);
        return '<div class="ct-item"><span class="ct-fault">' + esc(tip.fault) + '</span>' +
          '<p>' + esc(tip.tip) + '</p>' +
          (cue && cue.text ? '<div class="ct-cue">“' + esc(cue.text) + '”</div>' : '') +
          (drills.length ? '<span class="ct-drills">Drills: ' + esc(drills.map((d) => d.name).join(' · ')) + '</span>' : '');
      }).join('') : '<p>This checkpoint slipped across the round — no single fault stood out. The basics below are the work.</p>');
      const bodyEl = details[i].querySelector('.cp-body');
      if (bodyEl) bodyEl.insertBefore(box, bodyEl.firstChild);
      details[i].open = true;   // flagged sections arrive open — that's what he came for
    });
  }

  function clearIndicators() {
    const strip = $('#swingDots');
    if (strip) strip.hidden = true;
    setLearnBadge(0);
    injectCoachTips(null);
  }

  // ---------------- hooks from app.js ----------------
  window.DugoutFilmShell = {
    onSwingOpened(session, swingId) {
      current = { sessionId: session.id, swingId, profileId: session.profileId };
      setStarState();
      applyAI();
      closeAll(true);
      renderIndicators(session, swingId);
    },
    onVideoMode() {
      current = null;
      setStarState();
      applyAI();
      closeAll(true);
      clearIndicators();
    },
    closeAll,
    applyAI
  };

  applyAI();
})();
