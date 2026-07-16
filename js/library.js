// GENERATED FILE — do not edit by hand.
// Source of truth: DugOut_Tip_Library_Seed_v0.2.xlsx (DUG-37).
// Regenerate with scripts/build_library.py after the trainer revises the sheet.
//
// 29 tip entries · 12 cue-glossary entries · 4 school presets · 12 engine rules
// `detector: null` means the fault is not measurable offline (needs ball flight, bat
// tracking, or detail pose lacks) — see docs/POSE-PROBE.md. Those faults are never
// guessed at; the checkpoint is graded on the entries that can be measured.

window.DUGOUT_LIBRARY = {
  tips: [
  {
    "id": "ST-01",
    "checkpoint": "stance",
    "fault": "Base too narrow or too wide",
    "detection": "Feet inside shoulder width (tippy, drifts during load) or far outside it (can't stride/rotate); knees locked straight",
    "tip": "Set an athletic base: feet about shoulder width or slightly wider, knees slightly bent, weight ~60/40 into the back leg",
    "drills": [
      {
        "name": "Mirror setup checks",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "stride-to-balance holds",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Strong athletic base",
      "Sit into your legs a little"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [
      "7-10"
    ],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "Little League University — Grip, Stance & Plate Coverage",
    "notes": "LL prescribes shoulder-width, knees bent, 40/60 front/back. Validate the 60/40 number.",
    "detector": "stance.baseWidth",
    "isToggle": false
  },
  {
    "id": "ST-02",
    "checkpoint": "stance",
    "fault": "Poor plate coverage",
    "detection": "Outside strikes untouched; bat can't reach outer third at contact frames; hitter set up too far off the plate (or crowding it)",
    "tip": "Set distance with the coverage check: from your stance, the barrel should reach the outside corner",
    "drills": [
      {
        "name": "Bat-to-outside-corner setup check before each round",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Touch the outside corner, then set up",
      "Own the whole plate"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "Little League University",
    "notes": "LL's named check: bat placed at the corner nearest the catcher from the stance.",
    "detector": null,
    "isToggle": false
  },
  {
    "id": "ST-03",
    "checkpoint": "stance",
    "fault": "Death-grip / palm grip",
    "detection": "White-knuckle grip, bat buried in palms; wrists stiff through the zone; tension visible in forearms/shoulders at setup",
    "tip": "Hold the bat in the fingers, relaxed; knuckles roughly aligned (straight line or slightly shifted is fine)",
    "drills": [
      {
        "name": "Grip resets between reps",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "waggle to stay loose",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Hold it like a bird — firm enough it can't fly, loose enough it lives",
      "Loose hands are quick hands"
    ],
    "cuesToAvoid": [
      "Line up your door-knocking knuckles' as a rigid rule (LL allows a range)"
    ],
    "avoidPhrases": [
      "line up your door-knocking knuckles"
    ],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [
      "7-10"
    ],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "Little League Univ.; Concord Sports (grip tension)",
    "notes": "LL: bat at base of fingers, lightly wrapped; knuckle alignment has tolerance.",
    "detector": null,
    "isToggle": false
  },
  {
    "id": "ST-04",
    "checkpoint": "stance",
    "fault": "Weight dead-even or on the front foot at setup",
    "detection": "No load available; first move is a lean back (wasted motion) or straight lunge forward",
    "tip": "Start with slight rear-side favor (~60/40) so the load has somewhere to go",
    "drills": [
      {
        "name": "Setup checks",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "load-and-hold",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Start loaded, stay loaded",
      "Give your load a head start"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "Little League University",
    "notes": "May be too fine-grained for 7–10; trainer call.",
    "detector": "stance.weightBias",
    "isToggle": false
  },
  {
    "id": "LD-01",
    "checkpoint": "load",
    "fault": "No load — swing starts flat-footed",
    "detection": "No rhythm/gather before the pitch; hands and hips never move back; all-arms swing follows",
    "tip": "Learn to load the upper and lower half together before the swing launches",
    "drills": [
      {
        "name": "Hook 'Em drill (Driveline)",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Gather before you go",
      "Get your engine started early"
    ],
    "cuesToAvoid": [
      "Internal body-part checklists during live reps (see Engine Rules ER-02)"
    ],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "A",
    "sources": "Driveline Baseball 2022 drill library",
    "notes": "Verified fault→drill mapping (Hook 'Em = fails to load upper and lower half).",
    "detector": "load.noLoad",
    "isToggle": false
  },
  {
    "id": "LD-02",
    "checkpoint": "load",
    "fault": "Lunging / drifting forward (no back-hip load)",
    "detection": "Weight leaks onto the front leg during the stride; head drifts forward past center; hips slide instead of hinge",
    "tip": "Load into the back hip / posterior chain and hold it through the stride",
    "drills": [
      {
        "name": "Step Back drill",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "Kershaw drill (Driveline)",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Load the back pocket",
      "Hips back, then turn"
    ],
    "cuesToAvoid": [
      "Stay back' repeated verbally every rep — prefer the drill fix over the words"
    ],
    "avoidPhrases": [
      "stay back"
    ],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "A",
    "sources": "Driveline Baseball 2022",
    "notes": "Verified: Step Back & Kershaw teach loading into back hip; targets lunging/overstriding.",
    "detector": "load.drift",
    "isToggle": false
  },
  {
    "id": "LD-03",
    "checkpoint": "load",
    "fault": "Bat wrap",
    "detection": "At full load the barrel wraps behind the head toward the pitcher; long route to the ball follows",
    "tip": "Keep the barrel out of the wrap: load the hands without pointing the barrel at the pitcher",
    "drills": [
      {
        "name": "Load-position holds on tee",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "mirror checks",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Show the pitcher the knob, not the barrel"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Traditional",
      "modern agree"
    ],
    "tier": "B",
    "sources": "Practitioner consensus (multiple instruction sources)",
    "notes": "Common youth fault; not in verified A-corpus. Validate phrasing.",
    "detector": null,
    "isToggle": false
  },
  {
    "id": "LD-04",
    "checkpoint": "load",
    "fault": "Hitch (hands drop as the pitch arrives)",
    "detection": "Hands dip below load position right at launch; late on average velocity despite good bat speed",
    "tip": "Time the load earlier so any hand movement finishes before launch",
    "drills": [
      {
        "name": "Early-load front toss ('be ready when the ball leaves the hand')",
        "rung": "frontToss",
        "weighted": false
      },
      {
        "name": "load-and-hold variations",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Beat the ball to your load",
      "Done loading before the release"
    ],
    "cuesToAvoid": [
      "Trying to surgically delete the hitch if timing is fine (many pros hitch productively)"
    ],
    "avoidPhrases": [],
    "ageBands": [
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "B",
    "sources": "Practitioner consensus",
    "notes": "Driveline-school view: fix timing, not the movement itself. Validate.",
    "detector": null,
    "isToggle": false
  },
  {
    "id": "SR-01",
    "checkpoint": "stride",
    "fault": "Too early — premature weight shift + early hip extension",
    "detection": "Weight fully on front leg well before contact; hitter comes out of the hip hinge before front side firms up; rotation happens around the front leg; bat path steepens",
    "tip": "Keep the hinge through the stride; firm the front side before rotation fires",
    "drills": [
      {
        "name": "Step Backs",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "Feet Together Stride Away",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "Offset Open",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "Hook 'Em (Driveline timing menu)",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Stride to launch, not to swing",
      "Land soft, then fire"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "A",
    "sources": "Driveline (Glaum) 2021 — 'Too Early'",
    "notes": "Verified incl. the on-video signature. Plain video is the preferred diagnostic for timing (not sensors).",
    "detector": "stride.early",
    "isToggle": false
  },
  {
    "id": "SR-02",
    "checkpoint": "stride",
    "fault": "Overstriding",
    "detection": "Stride length blows past athletic base; head drops and drifts; base too wide to rotate at landing",
    "tip": "Shorten to a controlled stride that lands with weight still back",
    "drills": [
      {
        "name": "Step Back drill",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "Kershaw drill",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Small step, big turn"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "A",
    "sources": "Driveline Baseball 2022",
    "notes": "Same verified drill family as LD-02.",
    "detector": "stride.overstride",
    "isToggle": false
  },
  {
    "id": "SR-03",
    "checkpoint": "stride",
    "fault": "Stepping in the bucket (stride flies open)",
    "detection": "Front foot lands toward foul territory (pull side); hips pre-open; outer-half coverage gone",
    "tip": "Stride to a spot that keeps the front side closed until launch",
    "drills": [
      {
        "name": "Stride-direction target (object/line to stride onto)",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "angled tee work to the oppo gap",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Stride down the line",
      "Step to the pitcher"
    ],
    "cuesToAvoid": [
      "Shaming fear — at 7–10 this is usually ball-fear: fix with soft toss/wiffle progression first"
    ],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "NTX Swing Lab + practitioner consensus",
    "notes": "Detection is easy for the vision engine (foot landing direction). Validate the fear-first note.",
    "detector": "stride.bucket",
    "isToggle": false
  },
  {
    "id": "SR-04",
    "checkpoint": "stride",
    "fault": "Front-foot spin / landing open",
    "detection": "Front foot lands (or immediately spins) pointing at the pitcher or beyond; front hip leaks open at landing",
    "tip": "Land with the front foot mostly closed (~45° or less) so the hips have something to fire against",
    "drills": [
      {
        "name": "Stride-and-hold checks",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "Offset Closed variations",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Land closed, finish open"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "NTX Swing Lab + consensus",
    "notes": "Validate the 45° tolerance for youth.",
    "detector": null,
    "isToggle": false
  },
  {
    "id": "SR-05",
    "checkpoint": "stride",
    "fault": "Too late — swing starts after the window",
    "detection": "Contact consistently deep; barrel accelerating at/after contact frame; jammed on average fastballs",
    "tip": "Start the load/stride earlier relative to release; train against game-speed timing",
    "drills": [
      {
        "name": "High-velocity front toss simulating game reaction time (Driveline modality)",
        "rung": "frontToss",
        "weighted": false
      },
      {
        "name": "machine rounds at +5 mph",
        "rung": "live",
        "weighted": false
      }
    ],
    "cues": [
      "Be on time for the fastball, adjust to the rest"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "B",
    "sources": "Driveline constraint-training modality (verified) applied to timing-late (inference)",
    "notes": "The modality is Tier A; the specific application to 'late' is B.",
    "detector": "stride.late",
    "isToggle": false
  },
  {
    "id": "SR-06",
    "checkpoint": "stride",
    "fault": "Head movement through the stride",
    "detection": "Head displaces forward/down noticeably between load and contact frames; eyes level changes",
    "tip": "Quiet the head: stride under a still head so the eyes stay on one plane",
    "drills": [
      {
        "name": "Stride-and-hold with head-position check",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "balance-beam strides",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Keep your eyes in a box",
      "Quiet head, loud hips"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "Practitioner consensus (video-detectable)",
    "notes": "A natural vision-engine metric; validate tolerance.",
    "detector": "stride.headMove",
    "isToggle": false
  },
  {
    "id": "HF-01",
    "checkpoint": "hips",
    "fault": "Slow/weak rotation — hips don't drive the swing",
    "detection": "Low rotational speed; hands visibly out-race the hips; weak exit velocity despite decent contact",
    "tip": "Train rotational power so the hips lead and accelerate the barrel",
    "drills": [
      {
        "name": "Med-ball side toss",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "Offset-Closed rope-ball swings into Plyo wall",
        "rung": "tee",
        "weighted": true
      },
      {
        "name": "shuffle swings w/ overloaded bat",
        "rung": "tee",
        "weighted": true
      },
      {
        "name": "Hook 'Em short-bat (pull-side gap)",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "underload HR derby off front toss (Driveline 2019 rotation menu)",
        "rung": "frontToss",
        "weighted": true
      }
    ],
    "cues": [
      "Turn fast",
      "Hips start the party"
    ],
    "cuesToAvoid": [
      "Squish the bug' (see Cue Glossary CG-01)"
    ],
    "avoidPhrases": [
      "squish the bug"
    ],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "A",
    "sources": "Driveline 2019 youth programming",
    "notes": "Verified 5-drill rotation menu with set/reps. Weighted-implement safety by age is an open research gap — trainer sets limits.",
    "detector": "hips.rotationSpeed",
    "isToggle": false
  },
  {
    "id": "HF-02",
    "checkpoint": "hips",
    "fault": "No hip–shoulder separation",
    "detection": "Hips and shoulders rotate as one block; no stretch between pelvis and torso at launch",
    "tip": "Create separation: hips fire first while the shoulders stay closed a beat longer",
    "drills": [
      {
        "name": "Med-ball step-behind throws",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "separation holds at landing",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "Pivot Pickoff-style drills",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Hips go, shoulders wait"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "B",
    "sources": "NTX Swing Lab + consensus",
    "notes": "Detectable on video (pelvis vs shoulder line at launch).",
    "detector": "hips.separation",
    "isToggle": false
  },
  {
    "id": "HF-03",
    "checkpoint": "hips",
    "fault": "Flying open (front shoulder pulls out)",
    "detection": "Front shoulder yanks toward pull side before contact; barrel drags; oppo-half whiffs and weak pulls",
    "tip": "Keep the front shoulder in the zone longer; direct the swing to the big part of the field",
    "drills": [
      {
        "name": "Offset Open tee work",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "oppo-gap front toss rounds",
        "rung": "frontToss",
        "weighted": false
      }
    ],
    "cues": [
      "Stay in the zone longer",
      "Hit it to the shortstop's left ear"
    ],
    "cuesToAvoid": [
      "Keep your shoulder in' repeated as a body command (internal focus)"
    ],
    "avoidPhrases": [
      "keep your shoulder in"
    ],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "B",
    "sources": "Concord (excessive upper rotation) + Driveline Offset Open (A-adjacent)",
    "notes": "Offset Open's direction-training role is verified; the fault framing here is B.",
    "detector": "hips.flyOpen",
    "isToggle": false
  },
  {
    "id": "HF-04",
    "checkpoint": "hips",
    "fault": "Back-side collapse",
    "detection": "Back knee/hip caves toward the plate and posture drops; shoulders tilt skyward; pop-ups and topspin pulls",
    "tip": "Rotate on a stable back side: drive the back hip around, not down",
    "drills": [
      {
        "name": "Beltre drill (knee-drop constraint vs leaking)",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "posture holds",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "wall-distance checks",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Tall turn",
      "Belt buckle to the pitcher, not the sky"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "NTX Swing Lab; Driveline Beltre drill (A-adjacent)",
    "notes": "Beltre drill verified in the attack-angle context (CT-04); reuse here is B.",
    "detector": "hips.backsideCollapse",
    "isToggle": false
  },
  {
    "id": "CT-01",
    "checkpoint": "contact",
    "fault": "Ground-ball contact / can't elevate the low pitch",
    "detection": "Chronic ground balls especially on pitches down; early extension while rotating; barrel under-plane too late",
    "tip": "Learn to elevate the low pitch with posture and path, not scooping",
    "drills": [
      {
        "name": "Low Tee drill (Driveline)",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Drive the low ball to the gap"
    ],
    "cuesToAvoid": [
      "Get on top of it' / 'chop down' (CG-02)"
    ],
    "avoidPhrases": [
      "get on top of it",
      "chop down"
    ],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "A",
    "sources": "Driveline Baseball 2022",
    "notes": "Verified: Low Tee = elevate the low pitch; fixes ground-ball contact + early extension.",
    "detector": null,
    "isToggle": false
  },
  {
    "id": "CT-02",
    "checkpoint": "contact",
    "fault": "Push pattern / can't handle the high pitch",
    "detection": "Weak contact or whiffs on top-third pitches; hands push the barrel with a steep, late path up high",
    "tip": "Train high-pitch posture with a flatter path",
    "drills": [
      {
        "name": "High Tee drill (Driveline)",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Flat and quick up there"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "A",
    "sources": "Driveline Baseball 2022",
    "notes": "Verified: High Tee = high-pitch posture, flatter path, for hitters with a 'push pattern'.",
    "detector": null,
    "isToggle": false
  },
  {
    "id": "CT-03",
    "checkpoint": "contact",
    "fault": "Rolling over / weak opposite-field contact",
    "detection": "Topspin grounders to the pull side; wrists roll before contact on outer-half pitches; weak oppo flares",
    "tip": "Build swing depth and direction — learn productive oppo contact",
    "drills": [
      {
        "name": "Offset Open tee drill (Driveline)",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Hit the inside half of the ball to the big field"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "A",
    "sources": "Driveline 2022 + official drill video",
    "notes": "Verified fault→drill mapping (2-1 dissent was on tee-position gloss only).",
    "detector": null,
    "isToggle": false
  },
  {
    "id": "CT-04",
    "checkpoint": "contact",
    "fault": "Attack angle too steep for the bat speed",
    "detection": "Topspin on well-struck balls; misses/fouls on top-third pitches; uppercut visibly outruns strength",
    "tip": "Flatten the entry: match attack angle to what your bat speed can support",
    "drills": [
      {
        "name": "High tee + barrel-overloaded bat",
        "rung": "tee",
        "weighted": true
      },
      {
        "name": "Beltre drill (stop leaking forward)",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "high tee with long bat from the shoulder (arms can't take over) — Driveline 2019 menu",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Line drives over the middle infield"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern constraint-led"
    ],
    "tier": "A",
    "sources": "Driveline 2019 youth programming",
    "notes": "Verified 3-drill menu (1×12 swings each). Do NOT carry the sub-8.0 Blast threshold claim (refuted).",
    "detector": null,
    "isToggle": false
  },
  {
    "id": "CT-05",
    "checkpoint": "contact",
    "fault": "Casting (hands push out, barrel away early)",
    "detection": "Elbow gets outside the hands early in the swing; wide barrel arc; long to the ball, weak on inside pitches",
    "tip": "Keep the hands inside the barrel's turn — tight turn first, extension after contact",
    "drills": [
      {
        "name": "Tight-turn / half-turn drills",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "short-bat work",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "inside-pitch tee at the belt",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Tight turn, then long through the ball"
    ],
    "cuesToAvoid": [
      "Knob to the ball' as a universal fix (contested — CG-05)"
    ],
    "avoidPhrases": [
      "knob to the ball"
    ],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Contested between schools"
    ],
    "tier": "B",
    "sources": "Scott Hemond (detection = elbow outside hands) + consensus",
    "notes": "Detection rule is crisp for the vision engine. Fix phrasing is school-dependent — trainer call.",
    "detector": "contact.casting",
    "isToggle": false
  },
  {
    "id": "CT-06",
    "checkpoint": "contact",
    "fault": "Bat drag (rear elbow leads the hands)",
    "detection": "Rear elbow visibly in front of the hands/knob during the turn; barrel late and under; common in 8–12s swinging heavy bats",
    "tip": "Let the barrel turn with the hands, not behind the elbow; check bat weight first",
    "drills": [
      {
        "name": "Top-hand-only drills with light bat",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "short bat tight turns",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "bat-size check",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Throw the barrel, not the elbow"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13"
    ],
    "emphasize": [],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "ImproveYourHitting (detection verbatim) + consensus",
    "notes": "Bat too heavy is the #1 cause at 7–12 — engine should suggest equipment check first. Validate.",
    "detector": "contact.batDrag",
    "isToggle": false
  },
  {
    "id": "CT-07",
    "checkpoint": "contact",
    "fault": "Head pulls off the ball at contact",
    "detection": "Face rotates toward pull side before contact frame; eyes leave the contact point; swing-and-miss on soft stuff away",
    "tip": "See contact: keep the eyes on the point of contact through the hit",
    "drills": [
      {
        "name": "Two-ball soft toss (call the color)",
        "rung": "softToss",
        "weighted": false
      },
      {
        "name": "tee work watching the bat hit the ball",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "See it hit the bat"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [
      "7-10"
    ],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "Practitioner consensus; Concord (early head lift)",
    "notes": "Classic youth fault; vision-engine detectable (face angle at contact).",
    "detector": "contact.headPull",
    "isToggle": false
  },
  {
    "id": "FN-01",
    "checkpoint": "finish",
    "fault": "Cutting the swing off / decelerating at contact",
    "detection": "Bat visibly slowing into contact; short abrupt finish; weak grounders & pop-ups despite on-time swing",
    "tip": "Swing through the ball — accelerate to a full finish, contact is on the way",
    "drills": [
      {
        "name": "Extension visualization (reach toward the pitcher)",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "finish holds",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "underload bat speed rounds",
        "rung": "tee",
        "weighted": true
      }
    ],
    "cues": [
      "Hit through it, not to it",
      "Finish your swing"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "Concord Sports (premature termination/insufficient extension)",
    "notes": "Stock youth fault; easy video detection (barrel speed at/after contact).",
    "detector": null,
    "isToggle": false
  },
  {
    "id": "FN-02",
    "checkpoint": "finish",
    "fault": "Balance lost at the finish",
    "detection": "Hitter falls toward the plate/pitcher/backward after the swing; needs a step to recover",
    "tip": "Finish in balance — you should be able to freeze your finish",
    "drills": [
      {
        "name": "Balanced-finish holds (freeze 2 counts)",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "slow-motion shadow swings",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Freeze your finish",
      "Swing hard, land like a statue"
    ],
    "cuesToAvoid": [],
    "avoidPhrases": [],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [
      "7-10"
    ],
    "schoolTags": [
      "Universal"
    ],
    "tier": "B",
    "sources": "Concord Sports",
    "notes": "LTAD-friendly: balance is explicit Discover-stage vocabulary ('Balance when swinging').",
    "detector": "finish.balance",
    "isToggle": false
  },
  {
    "id": "FN-03",
    "checkpoint": "finish",
    "fault": "Low chop finish",
    "detection": "Bat finishes at/below the waist; path never got on plane; often pairs with 'swing down' teaching",
    "tip": "Let the finish come up naturally — shoulder height or above",
    "drills": [
      {
        "name": "Tee work with finish-height checkpoint",
        "rung": "tee",
        "weighted": false
      },
      {
        "name": "high-finish shadow swings",
        "rung": "tee",
        "weighted": false
      }
    ],
    "cues": [
      "Finish over your shoulder"
    ],
    "cuesToAvoid": [
      "Swing down through the ball' (CG-02)"
    ],
    "avoidPhrases": [
      "swing down through the ball"
    ],
    "ageBands": [
      "7-10",
      "11-13",
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "Modern",
      "traditional mostly agree"
    ],
    "tier": "B",
    "sources": "Concord (improper finish height) + consensus",
    "notes": "—",
    "detector": "finish.height",
    "isToggle": false
  },
  {
    "id": "FN-04",
    "checkpoint": "finish",
    "fault": "One-hand vs two-hand finish treated as a fault",
    "detection": "(Style, not a fault) — release of the top hand after extension varies by hitter and pitch location",
    "tip": "Either finish is acceptable if contact & extension are complete; the ball's location moves the finish",
    "drills": [],
    "cues": [
      "Your finish belongs to you"
    ],
    "cuesToAvoid": [
      "Forcing two hands on every swing as a blanket rule"
    ],
    "avoidPhrases": [],
    "ageBands": [
      "14-18"
    ],
    "emphasize": [],
    "schoolTags": [
      "School-of-thought toggle (Lau lineage popularized top-hand release)"
    ],
    "tier": "C",
    "sources": "MaxBP (finish varies w/ location); HS coaching forums",
    "notes": "This is a PHILOSOPHY TOGGLE in the app, not a fault entry. Trainer picks a default.",
    "detector": null,
    "isToggle": true
  }
],

  cueGlossary: [
  {
    "id": "CG-01",
    "phrases": [
      "Squish the bug"
    ],
    "phrase": "Squish the bug",
    "status": "deprecated",
    "statusText": "DEPRECATED — default red line",
    "lineage": "Traditional youth coaching",
    "why": "Keeps the back foot planted and kills weight transfer/hip drive; internal-focus; Driveline: 'most 13-year-olds with a smartphone know big leaguers don't squish the bug.'",
    "replacement": "'Turn fast' / let the back foot release naturally",
    "tier": "A"
  },
  {
    "id": "CG-02",
    "phrases": [
      "Swing down",
      "chop down at the ball"
    ],
    "phrase": "Swing down",
    "status": "deprecated",
    "statusText": "DEPRECATED — default red line",
    "lineage": "Traditional",
    "why": "Pro swings attack slightly up to match pitch plane; chopping teaches ground-ball contact and low finishes.",
    "replacement": "'Line drives over the middle infield' / match the plane of the pitch",
    "tier": "A"
  },
  {
    "id": "CG-03",
    "phrases": [
      "Keep your back elbow up"
    ],
    "phrase": "Keep your back elbow up",
    "status": "contested",
    "statusText": "CONTESTED",
    "lineage": "Traditional youth coaching",
    "why": "No mechanical consensus; elbow position at setup varies among elite hitters; often creates tension and bat drag in small players.",
    "replacement": "Say nothing about the elbow; check bat weight (CT-06)",
    "tier": "B"
  },
  {
    "id": "CG-04",
    "phrases": [
      "Level swing"
    ],
    "phrase": "Level swing",
    "status": "contested",
    "statusText": "CONTESTED",
    "lineage": "Traditional",
    "why": "Ambiguous: level to the ground teaches chopping vs level to the pitch plane (correct). Kids hear 'flat.'",
    "replacement": "'Swing on the pitch's plane'",
    "tier": "B"
  },
  {
    "id": "CG-05",
    "phrases": [
      "Knob to the ball"
    ],
    "phrase": "Knob to the ball",
    "status": "contested",
    "statusText": "CONTESTED — school-dependent",
    "lineage": "Linear / Lau-descended teaching",
    "why": "Advocates: shortens the path. Critics ('turn the barrel' school): creates push patterns and late barrels. Genuine school disagreement — philosophy toggle.",
    "replacement": "School choice: 'knob to the ball' vs 'turn the barrel early'",
    "tier": "C"
  },
  {
    "id": "CG-06",
    "phrases": [
      "Turn the barrel"
    ],
    "phrase": "Turn the barrel",
    "status": "active",
    "statusText": "ACTIVE — modern school",
    "lineage": "Modern rotational/barrel-turn teaching",
    "why": "Emphasizes early barrel acceleration behind the ball rather than dragging the knob; pairs with catapult-style loads.",
    "replacement": "—",
    "tier": "C"
  },
  {
    "id": "CG-07",
    "phrases": [
      "Hips lead the hands"
    ],
    "phrase": "Hips lead the hands",
    "status": "active",
    "statusText": "ACTIVE",
    "lineage": "Rotational (Williams lineage)",
    "why": "Core rotational sequencing cue; matches kinetic-chain order.",
    "replacement": "— (still external-adjacent; fine)",
    "tier": "B"
  },
  {
    "id": "CG-08",
    "phrases": [
      "Squash it to right field"
    ],
    "phrase": "Squash it to right field",
    "status": "active",
    "statusText": "ACTIVE — preferred pattern",
    "lineage": "Modern external-focus",
    "why": "Target/field cues are external focus — the pattern research favors (ER-02). Template for slang capture: coach's own version of a target cue.",
    "replacement": "—",
    "tier": "A"
  },
  {
    "id": "CG-09",
    "phrases": [
      "See it hit the bat"
    ],
    "phrase": "See it hit the bat",
    "status": "active",
    "statusText": "ACTIVE",
    "lineage": "Universal",
    "why": "External focus on the contact point; classic youth vision cue.",
    "replacement": "—",
    "tier": "B"
  },
  {
    "id": "CG-10",
    "phrases": [
      "Freeze your finish"
    ],
    "phrase": "Freeze your finish",
    "status": "active",
    "statusText": "ACTIVE",
    "lineage": "Universal (youth)",
    "why": "Balance-outcome cue; aligns with LTAD Discover-stage 'balance when swinging.'",
    "replacement": "—",
    "tier": "B"
  },
  {
    "id": "CG-11",
    "phrases": [
      "Throw your hands"
    ],
    "phrase": "Throw your hands",
    "status": "contested",
    "statusText": "CONTESTED",
    "lineage": "Linear-descended",
    "why": "Critics: produces arm-y, disconnected swings; defenders: quickness cue. School toggle.",
    "replacement": "'Turn fast' variants",
    "tier": "C"
  },
  {
    "id": "CG-12",
    "phrases": [
      "Stay back"
    ],
    "phrase": "Stay back",
    "status": "contested",
    "statusText": "CONTESTED — words vs drill",
    "lineage": "Universal traditional",
    "why": "The goal (back-hip load) is right, but repeated verbal correction is internal-ish and rarely sticks; the Step Back/Kershaw drills fix it structurally.",
    "replacement": "Prescribe LD-02 drills; cue 'load the back pocket'",
    "tier": "B"
  }
],

  schools: [
  {
    "preset": "Rotational (classic)",
    "lineage": "Ted Williams, 'The Science of Hitting' (1970)",
    "beliefs": "Hips lead the hands; slight uppercut to match pitch plane; rotation is the power source",
    "signatureCues": "'Hips lead the hands'; plane-matching cues",
    "emphasisIds": [
      "HF-01",
      "CT-04",
      "CG-07"
    ],
    "tier": "C",
    "notes": "Williams/Lau lineage claims did NOT survive strict verification — this sheet is drafted from general knowledge + SABR framing. Needs trainer validation more than any other sheet."
  },
  {
    "preset": "Linear / weight-shift",
    "lineage": "Charley Lau ('The Art of Hitting .300'), Lau Jr.",
    "beliefs": "Weight shift drives the swing; knob leads; top-hand release; contact-first",
    "signatureCues": "'Knob to the ball' (CG-05); one-hand finish accepted (FN-04)",
    "emphasisIds": [
      "SR-01",
      "CT-05"
    ],
    "tier": "C",
    "notes": "Same caveat as above."
  },
  {
    "preset": "Modern constraint-led",
    "lineage": "Driveline Baseball et al. (2016–present)",
    "beliefs": "Train outcomes (Big 3), not positions; drills/constraints over verbal cues; external focus; measure everything",
    "signatureCues": "Target/outcome cues (CG-08); minimal body-talk",
    "emphasisIds": [
      "LD-01",
      "SR-01",
      "HF-01",
      "CT-01"
    ],
    "tier": "A",
    "notes": "The best-documented school in the research corpus; the library's baseline ranking leans this way — flagged as a known bias for trainer balancing."
  },
  {
    "preset": "Contact-first youth (governing-body)",
    "lineage": "USA Baseball LTAD / Little League University",
    "beliefs": "Age-staged progression; fun and contact before mechanics; closed→open skills; balance vocabulary",
    "signatureCues": "'Freeze your finish' (CG-10); simple balance/contact cues",
    "emphasisIds": [
      "ST-01",
      "FN-02",
      "ER-05"
    ],
    "tier": "A",
    "notes": "This is less a swing philosophy than the age framework every philosophy must respect."
  }
],

  engineRules: [
  {
    "id": "ER-01",
    "rule": "Six-checkpoint evaluation per session (REVISED per Derell, Jul 16)",
    "meaning": "Every session outputs an evaluation for EACH of the six checkpoints — Stance, Load, Stride, Hips Fire, Contact, Finish — graded/assessed across all swings in the round, PLUS a single 'work on this next' priority focus as the headline. (Supersedes the earlier one-fix-only rule; the one-fix idea survives as the priority pointer so young hitters aren't overloaded.)",
    "tier": "A"
  },
  {
    "id": "ER-02",
    "rule": "External focus beats internal focus",
    "meaning": "Render cues about the ball, the field, the target, or the implement — not body parts. Motor-learning research (Wulf & Su 2007, replicated) shows internal body-focus cues degrade athletic performance. All baseline cues in this library are written external-first.",
    "tier": "A"
  },
  {
    "id": "ER-03",
    "rule": "Diagnose from patterns, not single results — patterns are also how progress is measured",
    "meaning": "Never conclude a mechanical fault from ONE batted-ball result (a pop-up ≠ dropped shoulder; mishits are usually timing/vision/approach). Faults are named from patterns across the session's swings. Progress over time is measured the same way, one level up — see ER-12.",
    "tier": "A"
  },
  {
    "id": "ER-04",
    "rule": "Verbal-first feedback; drills attached as recommendations (REVISED per Derell, Jul 16)",
    "meaning": "Initial feedback is the VERBAL correction, rendered in the active philosophy's cue vocabulary; recommended drill(s) attach beneath it as the practice prescription. Phrasing rule stands: verbal corrections are worded external-focus (ball/field/target language), not body-part commands — that is what the motor-learning evidence supports (ER-02).",
    "tier": "A"
  },
  {
    "id": "ER-05",
    "rule": "Age-gate mechanical adjustments",
    "meaning": "7–10 (Discover): keep determinations environmental, fun-first, drill-based; no fine mechanical surgery; fear-of-ball protocols where relevant. 12–14 (Progress): video-based self-observation and mechanical adjustments formally begin (LTAD). Phrase gates as 'introduced at', not 'forbidden before.'",
    "tier": "A"
  },
  {
    "id": "ER-06",
    "rule": "Growth-spurt caution at 14–16",
    "meaning": "During visible growth changes, bias determinations toward re-refining known skills in closed settings (tee → soft toss) and protecting movement quality, not adding new mechanics.",
    "tier": "A"
  },
  {
    "id": "ER-07",
    "rule": "Prescribe drills on the right rung",
    "meaning": "Drill ladder: tee → short soft toss (5–10 ft) → front toss / coach pitch → live. The engine prescribes at or one rung below the athlete's current level; tee work and front toss are staples at every age (in BP groups from 10–12 up), not remedial.",
    "tier": "A"
  },
  {
    "id": "ER-08",
    "rule": "Don't coach out functional adaptations",
    "meaning": "Youth 'flaws' can be functional adaptations to a growing body. If results are fine and the pattern is stable, the engine notes it and waits for a session pattern before recommending change.",
    "tier": "A"
  },
  {
    "id": "ER-09",
    "rule": "Frame every tip by outcome (Big 3)",
    "meaning": "Tag each determination with which outcome it serves: bat speed, bat-to-ball, or swing decisions — never cosmetics ('we don't make changes because of looks').",
    "tier": "A"
  },
  {
    "id": "ER-10",
    "rule": "Weighted implements: trainer-set age limits",
    "meaning": "Overload/underload bats and plyo balls appear in verified youth programming, but no verified source sets age/strength safety thresholds for 7–13. Until the trainer sets policy, the engine does not prescribe weighted implements below 13. OPEN ITEM for Mike-validation.",
    "tier": "B"
  },
  {
    "id": "ER-11",
    "rule": "Timing faults: diagnose from video, not sensors",
    "meaning": "Plain video is the preferred diagnostic for timing faults (too early/too late) — which is what DugOut has. Sensor data is supplementary, not required.",
    "tier": "A"
  },
  {
    "id": "ER-12",
    "rule": "Progress tracking via checkpoint trends (NEW, from Derell's Jul 16 review)",
    "meaning": "Each session writes its six checkpoint evaluations + per-fault frequencies (e.g. casting present in X% of swings) to the athlete profile. Improvement/adjustment over time = trend lines per checkpoint and per fault across sessions, plus outcome trends. Determinations should reference the trend where meaningful ('Contact grade up two levels since June'). This is the development-record payoff of the six-checkpoint rubric.",
    "tier": "A"
  }
],

  // Phrases that must never reach output in any rendering path (CG-01, CG-02).
  // They exist here only as red-line data.
  deprecatedCues: [
  "chop down at the ball",
  "squish the bug",
  "swing down"
]
};
