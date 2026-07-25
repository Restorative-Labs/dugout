// Dugout — shell v2 (DUG-39): account + roles, first-launch onboarding,
// the You area (profile / hitters / settings), and the coach Team dashboard.
//
// Loads after store/config/library and BEFORE app.js: if no account exists yet the
// onboarding overlay is already covering the app when the router first renders.
// Accounts here are local-only — the shape (role, name) is deliberately tiny so the
// real account system (DUG-7) replaces it without a data migration.
(function () {
  const CFG = window.DUGOUT_CONFIG;
  const Store = window.DugoutStore;
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

  const ROLE_LABEL = { parent: 'Parent', player: 'Player', coach: 'Coach' };

  // ---------------- role-aware chrome ----------------
  function role() {
    const a = Store.account();
    return a ? a.role : 'parent';
  }

  function applyRole() {
    const r = role();
    document.body.dataset.role = r;
    const navTeam = $('#navTeam');
    if (navTeam) navTeam.hidden = r !== 'coach';

    const who = $('#homeWho');
    if (who) who.firstChild.textContent =
      r === 'coach' ? "Who's up?" : r === 'player' ? 'Your rounds' : "Who's hitting?";
    const add = $('#addProfile');
    if (add) add.textContent = r === 'coach' ? '+ Add an athlete' : '+ Add a hitter';
    const hint = $('#noProfile');
    if (hint) hint.textContent =
      r === 'coach' ? 'Add your athletes to get started. Every round attaches to an athlete so their progress builds up over time.'
        : r === 'player' ? 'Set up your hitter profile to get started.'
          : 'Add a hitter to get started. Every round attaches to a profile so his progress builds up over time.';
  }

  // Small copy that changes with who's reading it.
  function cueLabel() {
    const r = role();
    return r === 'coach' ? 'Say this to your hitter' : r === 'player' ? 'Say it to yourself' : 'Say this to him';
  }

  // ---------------- onboarding ----------------
  const ob = { step: 0, roleChoice: null, name: '', band: '14-18', voice: undefined, birthYear: null };

  function obSteps() {
    const steps = ['welcome', 'role', 'age', 'name', 'profiles', 'voice', 'done'];
    return steps;
  }

  function obShow() {
    $('#onboard').hidden = false;
    ob.step = 0;
    obRender();
  }

  function obRender() {
    const steps = obSteps();
    const step = steps[ob.step];
    $('#obDots').innerHTML = steps.map((_, i) =>
      '<i class="' + (i === ob.step ? 'on' : i < ob.step ? 'done' : '') + '"></i>').join('');

    const body = $('#obBody');
    body.innerHTML = '';
    $('#obErr').hidden = true;
    $('#obBack').style.visibility = ob.step === 0 ? 'hidden' : 'visible';
    const next = $('#obNext');
    next.textContent = step === 'welcome' ? 'Get started'
      : step === 'done' ? 'Take the field'
        : step === 'voice' ? 'Finish ›' : 'Next ›';

    if (step === 'welcome') return obWelcome(body);
    if (step === 'role') return obRole(body);
    if (step === 'age') return obAge(body);
    if (step === 'name') return obName(body);
    if (step === 'profiles') return obProfiles(body);
    if (step === 'voice') return obVoice(body);
    if (step === 'done') return obDone(body);
  }

  function obWelcome(body) {
    const h = el('div', 'ob-hero');
    h.innerHTML =
      '<div class="plate"><svg viewBox="0 0 48 48"><path d="M8 8h32v18L24 42 8 26z" fill="none" stroke="#f5f2e8" stroke-width="2.5" stroke-linejoin="round"/><text x="24" y="26" text-anchor="middle" font-family="Oswald,sans-serif" font-weight="700" font-size="17" fill="#ffb838">D</text></svg></div>' +
      '<h1>Dug<span>out</span></h1>' +
      '<div class="tag">Film · Freeze · Fix</div>' +
      '<p>Film one cage round. Dugout finds every swing, grades the six checkpoints, and hands you the one thing to work on next — in words a kid actually gets.</p>';
    body.appendChild(h);
  }

  const ROLES = [
    {
      id: 'parent', b: "I'm a parent", s: 'I film my kid’s rounds and read the results together. Up to two hitters.',
      svg: '<svg viewBox="0 0 34 34"><circle cx="13" cy="10" r="4.5"/><path d="M5 28c0-5 3.5-8 8-8s8 3 8 8"/><circle cx="25" cy="13" r="3"/><path d="M20.5 28c.4-3.6 2.4-5.5 5.5-5.5 2.4 0 4.4 1.4 5 4"/></svg>'
    },
    {
      id: 'player', b: "I'm the hitter", s: 'I film my own swings and work the fixes myself.',
      svg: '<svg viewBox="0 0 34 34"><circle cx="17" cy="9" r="4.5"/><path d="M9 29c0-5.5 3.6-9 8-9s8 3.5 8 9M25 6l4-4"/></svg>'
    },
    {
      id: 'coach', b: "I'm a coach", s: 'I run a roster and want every athlete’s rounds and progress in one place.',
      svg: '<svg viewBox="0 0 34 34"><rect x="5" y="7" width="24" height="18" rx="2"/><path d="M11 25v4m12-4v4M10 17l5-5 4 4 5-6"/></svg>'
    }
  ];

  function obRole(body) {
    body.appendChild(el('div', 'ob-q', 'Who’s using Dugout?'));
    body.appendChild(el('p', 'ob-help', 'This sets up the right experience — you can’t pick wrong, and nothing is locked.'));
    const wrap = el('div', 'ob-roles');
    ROLES.forEach((r) => {
      const b = el('button', 'ob-role' + (ob.roleChoice === r.id ? ' on' : ''));
      b.innerHTML = r.svg + '<b>' + r.b + '</b><small>' + r.s + '</small><span class="tick">✓</span>';
      b.onclick = () => { ob.roleChoice = r.id; obRender(); };
      wrap.appendChild(b);
    });
    body.appendChild(wrap);
  }

  // Neutral age screen (COPPA practice: ask plainly, don't telegraph a "right" answer).
  // Thresholds pending Delilah's B2 review (DUG-42): parent/coach 18+, solo player 13+.
  function obAge(body) {
    body.appendChild(el('div', 'ob-q', 'What year were you born?'));
    body.appendChild(el('p', 'ob-help', 'Dugout is built around kids’ swings, so we check who’s holding the phone. This stays on the device.'));
    const f = el('div', 'ob-field');
    f.innerHTML = '<label>Birth year</label>';
    const sel = el('select');
    sel.appendChild(el('option', null, 'Select…')).value = '';
    const now = new Date().getFullYear();
    for (let y = now; y >= now - 100; y--) {
      const o = el('option', null, String(y));
      o.value = String(y);
      if (ob.birthYear === y) o.selected = true;
      sel.appendChild(o);
    }
    sel.onchange = () => { ob.birthYear = parseInt(sel.value, 10) || null; };
    f.appendChild(sel);
    body.appendChild(f);
  }

  function obAgeOk() {
    if (!ob.birthYear) return 'Pick your birth year to keep going.';
    const age = new Date().getFullYear() - ob.birthYear;
    if (ob.roleChoice === 'player' && age < 13) {
      return 'Dugout accounts for hitters under 13 are set up by a parent — hand the phone to yours, or go back and they can pick “I’m a parent.”';
    }
    if (ob.roleChoice !== 'player' && age < 18) {
      return 'A parent or coach account needs an adult. Go back and pick “I’m the hitter” if you’re the one swinging.';
    }
    return null;
  }

  function obName(body) {
    body.appendChild(el('div', 'ob-q', 'What’s your first name?'));
    body.appendChild(el('p', 'ob-help', ob.roleChoice === 'player'
      ? 'Your hitter profile gets built from this.'
      : 'Just so Dugout talks to you like a person.'));
    const f = el('div', 'ob-field');
    f.innerHTML = '<label>First name</label>';
    const inp = el('input');
    inp.id = 'obName';
    inp.maxLength = 24;
    inp.placeholder = ob.roleChoice === 'coach' ? 'e.g. Coach Mike' : 'e.g. Derell';
    inp.value = ob.name;
    inp.oninput = () => { ob.name = inp.value; };
    f.appendChild(inp);
    body.appendChild(f);
    setTimeout(() => inp.focus(), 120);
  }

  function obProfiles(body) {
    const r = ob.roleChoice;

    if (r === 'player') {
      body.appendChild(el('div', 'ob-q', 'Your hitter profile'));
      body.appendChild(el('p', 'ob-help', 'Every round you film attaches to this profile, so your progress builds up round over round.'));
      const card = el('div', 'ob-kid');
      card.innerHTML = '<span class="kn">' + esc(ob.name.trim() || 'You') + '</span><span class="kb">that’s you</span>';
      body.appendChild(el('div', 'ob-list')).appendChild(card);
      const f = el('div', 'ob-field');
      f.innerHTML = '<label>Age band — feedback is worded for the age</label>';
      const sel = el('select');
      CFG.AGE_BANDS.forEach((b) => {
        const o = el('option', null, CFG.AGE_BAND_LABEL[b]);
        o.value = b;
        if (b === ob.band) o.selected = true;
        sel.appendChild(o);
      });
      sel.onchange = () => { ob.band = sel.value; };
      f.appendChild(sel);
      body.appendChild(f);
      return;
    }

    const kid = r === 'coach' ? 'athlete' : 'hitter';
    body.appendChild(el('div', 'ob-q', r === 'coach' ? 'Build your roster' : 'Who are we coaching?'));
    body.appendChild(el('p', 'ob-help', 'Every round attaches to a profile — that’s how streaks and progress work. Add at least one ' + kid +
      (r === 'coach' ? '. You can add the rest of the roster any time.' : '.')));

    const list = el('div', 'ob-list');
    Store.profiles().forEach((p) => {
      const row = el('div', 'ob-kid');
      row.innerHTML = '<span class="kn">' + esc(p.name) + '</span><span class="kb">' + CFG.AGE_BAND_LABEL[p.ageBand] + '</span>';
      const x = el('button', 'kx', '✕');
      x.onclick = async () => { await Store.deleteProfile(p.id); obRender(); };
      row.appendChild(x);
      list.appendChild(row);
    });
    body.appendChild(list);

    if (Store.profiles().length < Store.maxProfiles(r)) {
      const f = el('div', 'ob-field');
      f.innerHTML = '<label>Add a ' + kid + '</label>';
      const inp = el('input');
      inp.placeholder = 'First name';
      inp.maxLength = 24;
      const sel = el('select');
      CFG.AGE_BANDS.forEach((b) => {
        const o = el('option', null, CFG.AGE_BAND_LABEL[b]);
        o.value = b;
        if (b === '11-13') o.selected = true;
        sel.appendChild(o);
      });
      sel.style.marginTop = '8px';
      const add = el('button', 'btn btn-ghost', '+ Add ' + kid);
      add.style.marginTop = '10px';
      add.onclick = () => {
        const name = inp.value.trim();
        if (!name) { inp.focus(); return; }
        try { Store.addProfile(name, sel.value, r); obRender(); } catch (e) { obError(e.message); }
      };
      f.appendChild(inp);
      f.appendChild(sel);
      f.appendChild(add);
      body.appendChild(f);
    }
  }

  function obVoice(body) {
    body.appendChild(el('div', 'ob-q', 'How should corrections sound?'));
    body.appendChild(el('p', 'ob-help', 'Dugout grades from a vetted tip library either way — this only sets the coaching voice. Fine-tune any time in You → My philosophy.'));
    const wrap = el('div', 'ob-voice');

    const sug = el('button', 'preset big' + (ob.voice === undefined || ob.voice === null ? ' on' : ''));
    sug.innerHTML = '<b>DugOut Suggested · recommended</b><small>The library’s own baseline — proven tips, plain words. Works great out of the box.</small>';
    sug.onclick = () => { ob.voice = null; obRender(); };
    wrap.appendChild(sug);

    (L.schools || []).forEach((sc) => {
      const b = el('button', 'preset big' + (ob.voice && ob.voice.preset === sc.preset ? ' on' : ''));
      b.innerHTML = '<b>' + esc(sc.preset) + '</b><small>' + esc((sc.beliefs || sc.notes || '').slice(0, 120)) + '</small>';
      b.onclick = () => { ob.voice = sc; obRender(); };
      wrap.appendChild(b);
    });
    body.appendChild(wrap);
  }

  function obDone(body) {
    const r = ob.roleChoice;
    const d = el('div', 'ob-done');
    d.innerHTML =
      '<span class="big">⚾</span>' +
      '<h2>You’re set, ' + esc(ob.name.trim() || 'coach') + '.</h2>' +
      '<p>' + (r === 'coach'
        ? 'Film any athlete’s round — Dugout finds each swing, grades the six checkpoints, and keeps every athlete’s progress on your Team board.'
        : r === 'player'
          ? 'Film a round — Dugout finds each swing, grades your six checkpoints, and gives you the one thing to fix next.'
          : 'Film a round — Dugout finds each swing, grades the six checkpoints, and gives you the one thing to say in the car ride home.') + '</p>';
    body.appendChild(d);
  }

  function obError(msg) {
    const e = $('#obErr');
    e.hidden = false;
    e.textContent = msg;
  }

  function applyVoiceChoice() {
    if (!ob.voice) {                       // OOB: DugOut Suggested
      Store.setActivePhilosophy('dugout-suggested');
      return;
    }
    const sc = ob.voice;
    const card = Store.newPhilosophy('My Philosophy', sc.preset);
    if (sc.emphasisIds && sc.emphasisIds.length) {
      const sel = {};
      CFG.CHECKPOINTS.forEach((cp) => {
        const ids = L.tips.filter((t) => t.checkpoint === cp && sc.emphasisIds.indexOf(t.id) >= 0).map((t) => t.id);
        if (ids.length) sel[cp] = ids;     // never blank a checkpoint entirely
      });
      card.tipSelections = sel;
    }
    card.active = true;
    Store.savePhilosophy(card);
    Store.setActivePhilosophy(card.id);
  }

  function obNextStep() {
    const steps = obSteps();
    const step = steps[ob.step];

    if (step === 'role' && !ob.roleChoice) return obError('Pick the one that sounds like you.');
    if (step === 'age') {
      const problem = obAgeOk();
      if (problem) return obError(problem);
    }
    if (step === 'name' && !ob.name.trim()) return obError('Just a first name is fine.');
    if (step === 'profiles') {
      if (ob.roleChoice === 'player') {
        const ps = Store.profiles();
        if (!ps.length) Store.addProfile(ob.name.trim() || 'Me', ob.band, 'player');
        else Store.updateProfile(ps[0].id, { name: ob.name.trim() || ps[0].name, ageBand: ob.band });
      } else if (!Store.profiles().length) {
        return obError('Add at least one — every round needs someone to attach to.');
      }
    }
    if (step === 'voice') applyVoiceChoice();

    if (ob.step >= steps.length - 1) return obFinish();
    ob.step++;
    obRender();
  }

  function obFinish() {
    Store.saveAccount({
      role: ob.roleChoice, name: ob.name.trim(), createdAt: Date.now(), onboarded: true,
      birthYear: ob.birthYear, ageVerifiedAt: Date.now()   // neutral gate; real posture = Delilah/DUG-42
    });
    const node = $('#onboard');
    node.classList.add('out');
    setTimeout(() => { node.hidden = true; node.classList.remove('out'); }, 320);
    applyRole();
    if (window.DugoutApp) { window.DugoutApp.go('home'); window.DugoutApp.render(); }
  }

  // ---------------- You: profile / hitters / settings ----------------
  let armDelete = null;   // two-tap delete (no confirm() dialogs in the wrapper)
  let armErase = false;
  let youAIOpen = false;  // AI-key mini-form expanded

  function renderYou() {
    const acc = Store.account() || { role: 'parent', name: '' };
    const r = acc.role;
    const body = $('#youBody');
    body.innerHTML = '';

    // identity
    const idc = el('div', 'ucard');
    idc.innerHTML =
      '<div class="uid-row"><div class="uid-ava">' + esc((acc.name || '?').slice(0, 1).toUpperCase()) + '</div>' +
      '<div><div class="uid-name">' + esc(acc.name || 'Set your name') + '</div>' +
      '<div class="uid-role">' + ROLE_LABEL[r] + ' account</div></div></div>';
    const nameRow = el('button', 'urow');
    nameRow.innerHTML = '<span class="ul">Name</span><span class="uv">' + esc(acc.name || '—') + '</span><span class="uc">›</span>';
    nameRow.onclick = () => openYouSheet('account');
    idc.appendChild(nameRow);
    body.appendChild(idc);

    // athletes / hitters / roster
    const label = r === 'coach' ? 'Roster' : r === 'player' ? 'My profile' : 'Hitters';
    const pc = el('div', 'ucard');
    pc.appendChild(el('h3', null, label));
    const profiles = Store.profiles();
    profiles.forEach((p) => {
      const row = el('div', 'uath');
      const open = el('button', 'urow');
      row.innerHTML =
        '<span class="an">' + esc(p.name) + '</span>' +
        '<span class="ab">' + CFG.AGE_BAND_LABEL[p.ageBand] + '</span>' +
        '<span class="ac">' + Store.sessions(p.id).length + ' rounds</span>';
      row.style.cursor = 'pointer';
      row.onclick = (e) => { if (e.target.classList.contains('adel')) return; openYouSheet('profile', p); };
      const del = el('button', 'adel' + (armDelete === p.id ? ' arm' : ''), armDelete === p.id ? 'sure?' : 'remove');
      del.onclick = async (e) => {
        e.stopPropagation();
        if (armDelete !== p.id) { armDelete = p.id; renderYou(); setTimeout(() => { if (armDelete === p.id) { armDelete = null; renderYou(); } }, 2600); return; }
        armDelete = null;
        await Store.deleteProfile(p.id);
        renderYou();
      };
      if (!(r === 'player' && profiles.length === 1)) row.appendChild(del);
      pc.appendChild(row);
    });
    if (profiles.length < Store.maxProfiles(r)) {
      const add = el('button', 'btn btn-ghost uadd', r === 'coach' ? '+ Add an athlete' : '+ Add a hitter');
      add.onclick = () => openYouSheet('profile', null);
      pc.appendChild(add);
    }
    body.appendChild(pc);

    // correction rules (the philosophy engine, in Derell's product language).
    // Coach: included with the plan. Parent/player: the "My Philosophy" add-on surface —
    // $4.99/mo at launch per DUG-25, free during beta so it's testable now.
    const phi = Store.activePhilosophy();
    const vc = el('div', 'ucard');
    vc.appendChild(el('h3', null, 'Correction rules'));
    if (r === 'coach') {
      const cur = el('button', 'urow');
      cur.innerHTML = '<span class="ul">' + esc(phi.name) + '</span>' +
        (phi.preset && phi.preset !== phi.name ? '<span class="uv">' + esc(phi.preset) + '</span>' : '') +
        '<span class="uc">›</span>';
      cur.onclick = () => window.DugoutApp.go('philosophy');
      vc.appendChild(cur);
      vc.appendChild(el('p', 'hint',
        'Included with your Coach plan. Your rules — which tips are in play, what gets red-lined, and your exact words — render every correction your roster sees.'));
    } else if (phi.source === 'suggested') {
      const up = el('div', 'upsell');
      up.innerHTML =
        '<b>Create your own correction rules</b>' +
        '<p>Pick the tips you believe in, red-line what you never want said, and put every correction in YOUR words.</p>' +
        '<span class="uprice">My Philosophy add-on · $4.99/mo at launch · <i>free during beta</i></span>';
      const go = el('button', 'btn btn-amber uadd', 'Customize now — beta');
      go.onclick = () => window.DugoutApp.go('philosophy');
      up.appendChild(go);
      vc.appendChild(up);
      vc.appendChild(el('p', 'hint', 'Right now he gets DugOut Suggested — the vetted library baseline. Solid out of the box.'));
    } else {
      const cur = el('button', 'urow');
      cur.innerHTML = '<span class="ul">' + esc(phi.name) + '</span><span class="uv">beta</span><span class="uc">›</span>';
      cur.onclick = () => window.DugoutApp.go('philosophy');
      vc.appendChild(cur);
      const rs = el('button', 'urow');
      rs.innerHTML = '<span class="ul">Reset to DugOut Suggested</span>';
      rs.onclick = () => { Store.setActivePhilosophy('dugout-suggested'); renderYou(); };
      vc.appendChild(rs);
    }
    body.appendChild(vc);

    // app
    const ac = el('div', 'ucard');
    ac.appendChild(el('h3', null, 'App'));

    // AI coaching key (DUG-40 R6): stored on this device only, never in the repo.
    const AI = window.DugoutAI;
    const aiRow = el('button', 'urow');
    aiRow.innerHTML = '<span class="ul">AI coaching key</span><span class="uv">' +
      (AI.hasKey() ? 'set ✓' : 'not set') + '</span><span class="uc">›</span>';
    ac.appendChild(aiRow);
    const aiBox = el('div', 'aibox');
    aiBox.hidden = !youAIOpen;
    aiBox.innerHTML =
      '<p class="hint" style="margin-top:0">Paste an Anthropic API key to turn on the AI coach (Deep Dive, AI-worded feedback) on this phone. It stays in this device’s storage only.</p>' +
      '<input id="aiKeyInput" type="password" placeholder="sk-ant-…" autocomplete="off">' +
      '<div class="srow" style="margin-top:8px">' +
      '<button class="btn btn-amber" id="aiKeySave">Save &amp; test</button>' +
      (AI.hasKey() ? '<button class="btn btn-ghost" id="aiKeyDrop">Remove</button>' : '') +
      '</div><p class="hint" id="aiKeyStatus"></p>';
    ac.appendChild(aiBox);
    aiRow.onclick = () => { youAIOpen = !youAIOpen; renderYou(); };
    if (youAIOpen) {
      $('#aiKeySave', aiBox).onclick = async () => {
        const v = $('#aiKeyInput', aiBox).value.trim();
        if (v) AI.setKey(v);
        $('#aiKeyStatus', aiBox).textContent = 'Testing…';
        const r = await AI.testConnection();
        $('#aiKeyStatus', aiBox).textContent = r.msg;
        if (window.DugoutFilmShell) window.DugoutFilmShell.applyAI();
        aiRow.querySelector('.uv').textContent = AI.hasKey() ? 'set ✓' : 'not set';
      };
      const drop = $('#aiKeyDrop', aiBox);
      if (drop) drop.onclick = () => {
        AI.setKey('');
        youAIOpen = false;
        if (window.DugoutFilmShell) window.DugoutFilmShell.applyAI();
        renderYou();
      };
    }

    const replay = el('button', 'urow');
    replay.innerHTML = '<span class="ul">Replay the welcome tour</span><span class="uc">›</span>';
    replay.onclick = () => { Store.clearAccount(); location.reload(); };
    ac.appendChild(replay);
    const erase = el('button', 'urow danger');
    erase.innerHTML = '<span class="ul">' + (armErase ? 'Tap again to erase everything' : 'Erase all data') + '</span>';
    erase.onclick = () => {
      if (!armErase) { armErase = true; renderYou(); setTimeout(() => { armErase = false; try { renderYou(); } catch (e) {} }, 2600); return; }
      localStorage.clear();
      try { indexedDB.deleteDatabase('dugout'); } catch (e) {}
      location.reload();
    };
    ac.appendChild(erase);
    body.appendChild(ac);

    body.appendChild(el('div', 'uver', 'Dugout · six checkpoints, one fix · data lives on this phone'));
  }

  // shared editor sheet: account name, or profile add/edit
  function openYouSheet(mode, profile) {
    const sheet = $('#youSheet');
    sheet.hidden = false;
    $('#ysErr').textContent = '';
    const bandWrap = $('#ysBandWrap');
    if (mode === 'account') {
      $('#ysTitle').textContent = 'Your name';
      $('#ysName').value = (Store.account() || {}).name || '';
      bandWrap.hidden = true;
    } else {
      const r = role();
      $('#ysTitle').textContent = profile ? 'Edit ' + profile.name : (r === 'coach' ? 'Add an athlete' : 'Add a hitter');
      $('#ysName').value = profile ? profile.name : '';
      $('#ysBand').value = profile ? profile.ageBand : '11-13';
      bandWrap.hidden = false;
    }
    $('#ysSave').onclick = () => {
      const name = $('#ysName').value.trim();
      if (!name) { $('#ysName').focus(); return; }
      try {
        if (mode === 'account') Store.saveAccount(Object.assign({}, Store.account(), { name }));
        else if (profile) Store.updateProfile(profile.id, { name, ageBand: $('#ysBand').value });
        else Store.addProfile(name, $('#ysBand').value);
        sheet.hidden = true;
        renderYou();
      } catch (e) { $('#ysErr').textContent = e.message; }
    };
    $('#ysCancel').onclick = () => { sheet.hidden = true; };
    setTimeout(() => $('#ysName').focus(), 60);
  }

  // ---------------- Team: the coach board ----------------
  const WEEK = 7 * 24 * 3600 * 1000;

  function renderTeam() {
    if (role() !== 'coach') { window.DugoutApp.go('home'); return; }
    const body = $('#teamBody');
    body.innerHTML = '';
    const profiles = Store.profiles();

    if (!profiles.length) {
      body.appendChild(el('p', 'hint', 'Add your athletes in the You tab and their rounds land here.'));
      return;
    }

    const now = Date.now();
    let active = 0;
    const rows = profiles.map((p) => {
      const sessions = Store.sessions(p.id);
      const week = sessions.filter((s) => now - s.startedAt < WEEK).length;
      if (week) active++;
      const lastEval = sessions.find((s) => s.evaluation);
      return { p, sessions, week, lastEval };
    });

    const sum = el('div', 'tsum');
    sum.innerHTML = '<b>' + active + ' of ' + profiles.length + '</b><span> swung in the last 7 days</span>';
    body.appendChild(sum);

    rows.forEach(({ p, sessions, week, lastEval }) => {
      const row = el('button', 'trow' + (week ? '' : ' stale'));
      const dots = CFG.CHECKPOINTS.map((cp) => {
        const e = lastEval && lastEval.evaluation[cp];
        const cls = !e || !e.assessed ? '' : e.pass ? 'ok' : 'no';
        return '<i class="' + cls + '" title="' + CFG.CHECKPOINT_LABEL[cp] + '"></i>';
      }).join('');
      const last = sessions.length
        ? 'Last round ' + new Date(sessions[0].startedAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
        : 'No rounds yet';
      row.innerHTML =
        '<span class="tn">' + esc(p.name) + '</span>' +
        '<span class="tdots">' + dots + '</span>' +
        '<span class="tmeta2">' + last + ' · <span class="twk' + (week ? '' : ' zero') + '">' + week + ' this week</span></span>';
      row.onclick = () => {
        Store.setLastProfile(p.id);
        window.DugoutApp.go('progress');
      };
      body.appendChild(row);
    });

    body.appendChild(el('p', 'hint', 'Dots are the six checkpoints from each athlete’s latest round — green passed, amber is the next thing to work on. Tap an athlete for streaks.'));
  }

  // ---------------- boot ----------------
  $('#obNext').onclick = obNextStep;
  $('#obBack').onclick = () => { if (ob.step > 0) { ob.step--; obRender(); } };

  applyRole();
  if (!Store.account()) obShow();

  window.DugoutShell = { renderYou, renderTeam, applyRole, cueLabel, role };
})();
