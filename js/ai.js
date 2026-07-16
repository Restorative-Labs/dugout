// Dugout — the single AI adapter.
//
// Every AI call in the app goes through here so the static demo degrades gracefully. With
// no backend, sessions still segment, detection still runs, and the Round Card still
// renders — composed from the detection results and library text alone.
//
// Budget rule (spec): ONE call per session for the rollup/verbal rendering. Never one per
// swing. Deep Dive is the exception — it is explicitly user-initiated, on demand, for a
// single chosen swing.
(function () {
  const CFG = window.DUGOUT_CONFIG;
  const ENDPOINT = 'https://api.anthropic.com/v1/messages';
  const MODEL = 'claude-sonnet-4-6';

  let available = null;   // null = untested, true/false once known

  async function call(body) {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(Object.assign({ model: MODEL }, body))
    });
    if (!res.ok) {
      available = false;
      throw new Error('ai-unavailable');
    }
    const data = await res.json();
    available = true;
    return (data.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('\n');
  }

  const parseJSON = (text) => JSON.parse((text || '').replace(/```json|```/g, '').trim());

  // ---- session rollup: one call, rewrites the verbal layer only ----
  //
  // The AI never decides pass/fail and never picks the fix. Detection and the rollup are
  // deterministic and identical offline; the AI only rewords the correction in the
  // parent's voice. That keeps the demo and the hosted build saying the same thing about
  // the same swing, and stops a language model from silently overruling the rubric.
  async function renderSession(payload) {
    const { feedback, profile, philosophy, perCheckpoint } = payload;
    const fails = CFG.CHECKPOINTS.filter((c) => perCheckpoint[c].assessed && !perCheckpoint[c].pass);
    const prompt =
      'You are a youth hitting coach talking to a parent who knows nothing about hitting. ' +
      'A round of ' + payload.swingCount + ' swings by a ' + CFG.AGE_BAND_LABEL[profile.ageBand] + ' year old was analyzed. ' +
      'Checkpoints failing: ' + (fails.length ? fails.map((f) => CFG.CHECKPOINT_LABEL[f]).join(', ') : 'none') + '. ' +
      'The one thing to work on: ' + (feedback.headline || 'nothing — clean round') + '. ' +
      'The coaching point: ' + (feedback.body || '') + '. ' +
      'The cue to say: ' + (feedback.cue ? feedback.cue.text : '(none)') + '. ' +
      'Rewrite ONLY the wording, warmer and plainer, for this parent to read aloud. ' +
      'Rules: keep the same substance and the same fix — do not change which fault is named. ' +
      'Use external focus (ball, field, target words), never body-part commands. ' +
      'Never use these phrases: ' + window.DUGOUT_LIBRARY.deprecatedCues.join('; ') + '. ' +
      (CFG.FUN_FIRST_BANDS.indexOf(profile.ageBand) >= 0
        ? 'This kid is young: keep it fun-first and environmental, no fine mechanical language. ' : '') +
      'Respond with ONLY JSON: {"headline":"short","body":"2-3 sentences","cue":"one short sentence to say out loud"}';

    const text = await call({ max_tokens: 700, messages: [{ role: 'user', content: prompt }] });
    const r = parseJSON(text);
    // A model that reaches for a red-lined cue gets ignored, not trusted.
    if (window.DugoutEvaluate.isDeprecated(r.headline) || window.DugoutEvaluate.isDeprecated(r.body) || window.DugoutEvaluate.isDeprecated(r.cue)) {
      throw new Error('ai-returned-deprecated-cue');
    }
    return r;
  }

  // Compose the Round Card verbally with no AI at all. This is what the trainer sees in the
  // static demo, so it has to read like a person wrote it — not like a template.
  function stubSession(payload) {
    const { feedback } = payload;
    return {
      headline: feedback.headline,
      body: feedback.body,
      cue: feedback.cue ? feedback.cue.text : null
    };
  }

  async function sessionFeedback(payload) {
    try {
      if (available === false) return { text: stubSession(payload), source: 'library' };
      const r = await renderSession(payload);
      return { text: r, source: 'ai' };
    } catch (e) {
      return { text: stubSession(payload), source: 'library' };
    }
  }

  window.DugoutAI = {
    sessionFeedback,
    call,
    parseJSON,
    isAvailable: () => available,
    markUnavailable: () => { available = false; }
  };
})();
