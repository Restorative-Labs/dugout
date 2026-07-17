// Dugout — tunable constants. Everything the spec calls "configurable in one place"
// lives here and nowhere else.
window.DUGOUT_CONFIG = {
  // ---- round caps (DUG-34) ----
  CAP_SECONDS: 90,
  CAP_SWINGS: 15,
  TIMER_PRESETS: [60, 90],       // DUG-35 in-app round lengths

  // ---- checkpoints: the spine of the whole product ----
  CHECKPOINTS: ['stance', 'load', 'stride', 'hips', 'contact', 'finish'],
  CHECKPOINT_LABEL: {
    stance: 'Stance', load: 'Load', stride: 'Stride',
    hips: 'Hips Fire', contact: 'Contact', finish: 'Finish'
  },

  // Fraction of a swing window each checkpoint phase occupies, contact-anchored.
  // 0 = start of window, 1 = end. Contact sits at CONTACT_ANCHOR.
  CONTACT_ANCHOR: 0.62,
  PHASE_WINDOWS: {
    stance:  [0.00, 0.14],
    load:    [0.12, 0.34],
    stride:  [0.32, 0.52],
    hips:    [0.50, 0.62],
    contact: [0.58, 0.72],
    finish:  [0.72, 1.00]
  },

  // ---- pass/fail (DUG-34) ----
  // Internal scores are NEVER displayed. Structure allows age-band overrides later.
  PASS_THRESHOLDS: {
    stance: 0.6, load: 0.6, stride: 0.6, hips: 0.6, contact: 0.6, finish: 0.6
  },
  PASS_THRESHOLD_DEFAULT: 0.6,

  // ---- ER-03: never name a fault seen in only one swing ----
  MIN_FAULT_SWINGS: 2,
  MIN_FAULT_SHARE: 0.25,

  // ---- ER-10: weighted implements gated by age until the trainer sets policy ----
  // Read conservatively: the 11-13 band spans under-13, so the whole band is excluded.
  WEIGHTED_IMPLEMENT_BANDS: ['14-18'],

  // ---- ER-07: drill ladder, lowest rung first ----
  DRILL_RUNGS: ['tee', 'softToss', 'frontToss', 'live'],

  // ---- segmentation ----
  MOTION_W: 192, MOTION_H: 108,   // downscale for frame differencing
  MOTION_PIXEL_DELTA: 18,         // per-pixel luma delta that counts as movement
  MOTION_SMOOTH_WIN: 5,           // median-smooth window (frames) — raw signal is noisy
  SPIKE_ENTER_MULT: 3.0,          // enter a swing above this * baseline
  SPIKE_EXIT_MULT: 1.6,           // ...and leave below this (hysteresis)
  // A youth swing is ~0.1-0.2s of blurred motion; bringing the bat back to the shoulder is
  // a slower, sustained half-second. At 0.25 this filter rejected the actual swings and
  // kept the resets — the exact inversion Derell caught on real footage.
  MIN_SWING_SEC: 0.08,

  // ---- ball detection: the gate that says a swing happened at all ----
  // Motion energy cannot tell a swing from a bat reset; both are just "movement". A ball
  // travelling through frame means a pitch happened. No ball, no swing.
  BALL_W: 480, BALL_H: 270,       // higher res than motion: a ball is ~15px at 1080p, so at
                                  // the 192x108 motion grid it would be under 2px
  BALL_MIN_AREA: 2,               // blob area (px at BALL_W x BALL_H)
  BALL_MAX_AREA: 140,             // bigger than this is the hitter, not the ball
  BALL_MAX_ASPECT: 3.0,           // motion-blurred balls streak, but not endlessly
  BALL_MIN_TRACK: 3,              // frames a candidate must persist to be a real track
  BALL_MAX_JUMP: 110,             // px a ball can travel between frames
  BALL_MIN_DISP: 45,              // total px travel — kills flickering leaves and noise
  BALL_NEAR_SEC: 0.7,             // a ball arriving this close to a motion spike = a swing
  // A first pass with only size/persistence filters produced 754 "tracks" in a 23s clip —
  // moving grass and leaves. What separates a ball from foliage is not size, it's motion
  // quality: a ball flies straight and fast, noise jitters in place.
  BALL_MIN_STRAIGHT: 0.82,        // |net displacement| / path length; a ball is ~1.0
  BALL_MIN_SPEED: 120,            // px/sec at BALL_W x BALL_H — leaves drift, balls fly
  BALL_MAX_TRACKS: 40,            // sanity: more than this means we're tracking noise
  MIN_GAP_SEC: 0.9,               // merge spikes closer than this into one swing
  PRE_PAD_SEC: 1.0,               // ~1s pre/post padding per spec
  POST_PAD_SEC: 1.0,
  AUDIO_CONFIRM_SEC: 0.35,        // audio transient this close to a motion peak = contact
  KEYFRAMES_PER_SWING: 24,        // raw is deleted, so frames must be extracted up front
  KEYFRAME_WIDTH: 540,
  KEYFRAME_QUALITY: 0.72,

  // ---- pose ----
  POSE_SAMPLES_PER_SWING: 16,     // frames per swing fed to MoveNet
  POSE_MIN_SCORE: 0.3,            // keypoint confidence floor
  POSE_CROP_PAD: 1.35,            // bbox padding for the second pass
  POSE_CROP_SIZE: 256,
  MODEL_URL: 'vendor/movenet/model.json',

  // ---- profiles ----
  MAX_PROFILES: 2,
  AGE_BANDS: ['7-10', '11-13', '14-18'],
  AGE_BAND_LABEL: { '7-10': '7–10', '11-13': '11–13', '14-18': '14–18' },
  // ER-05: 7-10 stays environmental/fun-first — no fine mechanical language.
  FUN_FIRST_BANDS: ['7-10'],

  DEBUG: true                     // logs detection confidence for threshold tuning
};
