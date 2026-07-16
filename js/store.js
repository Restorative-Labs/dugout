// Dugout — local persistence.
//
// Objects (profiles, sessions, philosophies) live in localStorage; keyframe blobs live
// in IndexedDB because they are far too big for localStorage's ~5MB string quota.
//
// Accounts/teams/cloud are out of scope, but every stored object already carries a
// profileId so they can bolt on later without a migration.
(function () {
  const CFG = window.DUGOUT_CONFIG;
  const K = {
    profiles: 'dugout.profiles',
    sessions: 'dugout.sessions',
    philosophies: 'dugout.philosophies',
    lastProfile: 'dugout.lastProfile',
    notes: 'dugout-notes'   // v1 key — kept so existing scouting notes survive the upgrade
  };

  const uid = (p) => p + '_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);

  function readJSON(key, fallback) {
    try {
      const v = localStorage.getItem(key);
      return v ? JSON.parse(v) : fallback;
    } catch (e) {
      console.warn('store: could not read ' + key, e);
      return fallback;
    }
  }

  function writeJSON(key, val) {
    try {
      localStorage.setItem(key, JSON.stringify(val));
      return true;
    } catch (e) {
      console.warn('store: could not write ' + key, e);
      return false;
    }
  }

  // ---------- IndexedDB for keyframes ----------
  let dbp = null;
  function db() {
    if (dbp) return dbp;
    dbp = new Promise((res, rej) => {
      const req = indexedDB.open('dugout', 1);
      req.onupgradeneeded = () => {
        const d = req.result;
        if (!d.objectStoreNames.contains('frames')) d.createObjectStore('frames');
      };
      req.onsuccess = () => res(req.result);
      req.onerror = () => rej(req.error);
    });
    return dbp;
  }

  async function idbPut(key, val) {
    const d = await db();
    return new Promise((res, rej) => {
      const tx = d.transaction('frames', 'readwrite');
      tx.objectStore('frames').put(val, key);
      tx.oncomplete = res;
      tx.onerror = () => rej(tx.error);
    });
  }

  async function idbGet(key) {
    const d = await db();
    return new Promise((res, rej) => {
      const tx = d.transaction('frames', 'readonly');
      const r = tx.objectStore('frames').get(key);
      r.onsuccess = () => res(r.result);
      r.onerror = () => rej(r.error);
    });
  }

  async function idbDel(key) {
    const d = await db();
    return new Promise((res) => {
      const tx = d.transaction('frames', 'readwrite');
      tx.objectStore('frames').delete(key);
      tx.oncomplete = res;
      tx.onerror = res;
    });
  }

  const Store = {
    // ---------- profiles (max 2) ----------
    profiles: () => readJSON(K.profiles, []),

    addProfile(name, ageBand) {
      const list = Store.profiles();
      if (list.length >= CFG.MAX_PROFILES) throw new Error('Only ' + CFG.MAX_PROFILES + ' profiles for now.');
      const p = { id: uid('ath'), name: name.trim(), ageBand, createdAt: Date.now() };
      list.push(p);
      writeJSON(K.profiles, list);
      Store.setLastProfile(p.id);
      return p;
    },

    updateProfile(id, patch) {
      const list = Store.profiles();
      const i = list.findIndex((p) => p.id === id);
      if (i < 0) return null;
      list[i] = Object.assign({}, list[i], patch);
      writeJSON(K.profiles, list);
      return list[i];
    },

    async deleteProfile(id) {
      writeJSON(K.profiles, Store.profiles().filter((p) => p.id !== id));
      for (const s of Store.sessions(id)) await Store.deleteSession(s.id);
      if (Store.lastProfileId() === id) localStorage.removeItem(K.lastProfile);
    },

    profile: (id) => Store.profiles().find((p) => p.id === id) || null,
    lastProfileId: () => localStorage.getItem(K.lastProfile),
    setLastProfile: (id) => localStorage.setItem(K.lastProfile, id),

    // ---------- sessions ----------
    sessions(profileId) {
      const all = readJSON(K.sessions, []);
      const list = profileId ? all.filter((s) => s.profileId === profileId) : all;
      return list.sort((a, b) => b.startedAt - a.startedAt);
    },

    session: (id) => readJSON(K.sessions, []).find((s) => s.id === id) || null,

    saveSession(session) {
      const all = readJSON(K.sessions, []);
      const i = all.findIndex((s) => s.id === session.id);
      if (i < 0) all.push(session); else all[i] = session;
      if (!writeJSON(K.sessions, all)) throw new Error('Out of storage — delete an old round and try again.');
      return session;
    },

    async deleteSession(id) {
      const s = Store.session(id);
      if (s) for (const sw of (s.swings || [])) await idbDel('frames_' + sw.id);
      writeJSON(K.sessions, readJSON(K.sessions, []).filter((x) => x.id !== id));
    },

    newSession(profileId, source, context) {
      return {
        id: uid('ses'), profileId, source, context: context || 'home',
        startedAt: Date.now(), durationSec: 0,
        swings: [],           // full Swing objects; swingIds[] is derivable
        evaluation: null, priorityFocus: null, capHit: null
      };
    },

    // ---------- swing keyframes (IndexedDB) ----------
    putFrames: (swingId, blobs) => idbPut('frames_' + swingId, blobs),
    getFrames: (swingId) => idbGet('frames_' + swingId),

    // ---------- philosophy ----------
    philosophies: () => readJSON(K.philosophies, []),

    savePhilosophy(card) {
      const all = Store.philosophies();
      const i = all.findIndex((p) => p.id === card.id);
      if (i < 0) all.push(card); else all[i] = card;
      writeJSON(K.philosophies, all);
      return card;
    },

    // The active card renders all feedback. Default is "DugOut Suggested" — the
    // library's own baseline ranking, no selection required to get going.
    activePhilosophy() {
      const all = Store.philosophies();
      return all.find((p) => p.active) || Store.suggestedPhilosophy();
    },

    setActivePhilosophy(id) {
      const all = Store.philosophies().map((p) => Object.assign({}, p, { active: p.id === id }));
      writeJSON(K.philosophies, all);
    },

    suggestedPhilosophy() {
      return {
        id: 'dugout-suggested',
        name: 'DugOut Suggested',
        preset: 'DugOut Suggested',
        tipSelections: {},        // {} = every library tip is in play
        priorities: CFG.CHECKPOINTS.slice(),
        redLineTipIds: [],
        slang: {},
        source: 'suggested',
        active: true
      };
    },

    newPhilosophy(name, preset) {
      return {
        id: uid('phi'), name, preset,
        tipSelections: {}, priorities: CFG.CHECKPOINTS.slice(),
        redLineTipIds: [], slang: {}, source: 'custom', active: false
      };
    },

    // ---------- notes (v1 carry-over) ----------
    notes: () => localStorage.getItem(K.notes) || '',
    saveNotes: (v) => localStorage.setItem(K.notes, v),

    uid
  };

  window.DugoutStore = Store;
})();
