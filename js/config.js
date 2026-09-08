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
  // Field tuning (DUG-34, Jul 26, "Three Swings.mov"): the smooth window is now TIME-based.
  // The old fixed 5-frame window assumed ~30 samples/sec, but rVFC at 4x playback drops
  // frames — measured ~7.5 samples/sec on real footage, turning "5 frames" into a ~0.7s
  // median that erased a real 0.2s swing (swing 2 of 3 vanished). The window is derived
  // from the measured sample cadence at runtime; MOTION_SMOOTH_WIN remains as the fallback.
  MOTION_SMOOTH_SEC: 0.24,        // target smoothing span in seconds (odd frame count, 3..9)
  MOTION_SMOOTH_WIN: 5,           // fallback median window (frames) if cadence unknown
  // Field tuning (DUG-34, Sep 8): 3.0 found ZERO swings on both regression clips.
  // Measured peak/baseline for REAL swings is 2.3-3.0x, not the 3-8x assumed below:
  // Three Swings.mov 2.69-2.98, pitch_01 2.79-2.99. The enter gate sat just above the
  // real signal, so no span ever opened and every round returned "No swings found".
  // At 2.4 both clips are exact against audio ground truth — Three Swings contacts at
  // 4.27 / 31.58 / 57.29s (truth ~4.3 / 31.6 / 57.3), pitch_01 at 7.43 / 20.55s.
  // 2.4 clears the noise floor with room on both sides; SPIKE_EXIT_MULT 1.6 unchanged.
  SPIKE_ENTER_MULT: 2.4,          // enter a swing above this * baseline
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
  // Field tuning (Jul 26): at delta 18 / area 2 a sunlit backyard (grass + bush shimmer,
  // compression noise) produced >20 blobs in 98% of frames and 1,800+ "tracks" — the
  // saturation guard tripped and the gate silently turned off. The ball is a high-contrast
  // white blob; shimmer is low-amplitude. A higher, ball-specific pixel delta plus a real
  // minimum area cuts noise ~8x while keeping the ball (measured sweep on real footage).
  BALL_PIXEL_DELTA: 26,           // luma delta for the BALL pass only (motion pass keeps 18)
  BALL_MIN_AREA: 4,               // blob area (px at BALL_W x BALL_H); 2 tracked pure noise
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
  // Field tuning (Jul 26): cage footage (pitch_01) produced 43 REAL tracks — the arriving
  // pitch plus the hit ball — and the old cap of 40 threw them all away. Genuine noise
  // saturation measures 388-1,800+ tracks (sunlit backyard); 80 separates the two cleanly.
  BALL_MAX_TRACKS: 80,            // sanity: more than this means we're tracking noise
  MIN_GAP_SEC: 0.9,               // merge spikes closer than this into one swing
  PRE_PAD_SEC: 1.0,               // ~1s pre/post padding per spec
  POST_PAD_SEC: 1.0,
  // Field tuning (Jul 26): on real self-toss footage the motion-energy peak lands mid-swing,
  // 0.5-0.7s BEFORE the contact ping — 0.35 missed every real contact. 0.75 snaps contact
  // to the ping on all three ground-truth swings without grabbing unrelated noise.
  AUDIO_CONFIRM_SEC: 0.75,        // audio transient this close to a motion peak = contact

  // ---- gate v2 (DUG-34 field failure, Jul 26) ----
  // The ball track alone cannot gate swings on real backyard footage: a moving bat tip and
  // body fragments produce ball-like tracks, and a noisy scene saturates the detector so the
  // gate turned itself off — practice waggles and walking to the camera then counted as
  // swings, while a clip whose noise tracks missed the swing windows returned ZERO swings
  // ("No swings found" on a clip with a real swing — the Single Single Error recording).
  // A motion spike now counts as a swing if a ball track OR a contact-audio transient lands
  // near it; a clip with neither signal anywhere falls back to motion-only (never zero out
  // an entire round for lack of confirmation signal).
  GATE_AUDIO_SEC: 1.0,            // audio ping within this of a motion peak confirms a swing
  MAX_SPIKE_MULT: 12,             // spikes above this x baseline are camera handling, not
                                  // swings (real swings measure 2.3-3.0x on the two
                                  // regression clips — the earlier "3-8x" note was
                                  // wrong and is what mis-set SPIKE_ENTER_MULT above;
                                  // walking into the lens to stop recording measured 20x)
  SWING_TIGHTEN_SEC: 3.0,         // spans longer than this are tightened around contact
                                  // before padding (walk-away bled a 7s window into swing 1)
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
  MAX_PROFILES: 2,                       // fallback when no account exists yet
  MAX_PROFILES_BY_ROLE: { parent: 2, player: 1, coach: 20 },   // DUG-39 local roles
  AGE_BANDS: ['7-10', '11-13', '14-18'],
  AGE_BAND_LABEL: { '7-10': '7–10', '11-13': '11–13', '14-18': '14–18' },
  // ER-05: 7-10 stays environmental/fun-first — no fine mechanical language.
  FUN_FIRST_BANDS: ['7-10'],

  DEBUG: true                     // logs detection confidence for threshold tuning
};
