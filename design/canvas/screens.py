#!/usr/bin/env python3
"""
DugOut — design canvas generator.

    screens.py  -> ORDERED MANIFEST (this file). The source of truth.
                   Adding a screen is inserting one entry in SCREENS.
    canvas.json -> generated
    *.dc.html   -> generated, one artboard per screen
                -> seeded with the design skill's helper, published as one artifact

RULES THIS FILE ENFORCES
  1. Insert in FLOW ORDER, never append. The sheet must read as the story.
  2. Slot codes are SEMANTIC (P-CONSENT), never positional (S07). Sequence
     numbers renumber on insert and every note silently points at the wrong
     picture.
  3. Every screen carries the RULING and the REASON, not just the layout —
     emitted as an HTML comment at the top of its artboard.
  4. Never render a number the product cannot honestly compute. Screens whose
     figures depend on data or an unruled decision are marked BLOCKED and say
     so on the face of the artboard.

Design vocabulary is lifted from the repo, not invented:
  css/app.css + css/shell.css  — tokens below
  Oswald 500/600/700 + Inter 400/500/600/700, self-hosted woff2 in css/fonts/
"""

import json
import os

OUT = os.path.dirname(os.path.abspath(__file__))

# ── tokens, copied from css/app.css :root — do not round, do not invent ──────
T = {
    "field": "#0d1f16", "field_2": "#132b1e", "chalk": "#f5f2e8",
    "chalk_dim": "#b9b5a6", "lights": "#ffb838", "lights_deep": "#e09a12",
    "flag": "#d94f3d", "line": "#2a4433", "card": "#12271b",
    "pass": "#5fbf7f",
}
PHONE_W, PHONE_H = 390, 844

BASE_CSS = """
    :root{--field:#0d1f16;--field-2:#132b1e;--chalk:#f5f2e8;--chalk-dim:#b9b5a6;
      --lights:#ffb838;--lights-deep:#e09a12;--flag:#d94f3d;--line:#2a4433;--card:#12271b;--pass:#5fbf7f}
    *{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
    body{background:var(--field);color:var(--chalk);font-family:'Inter',system-ui,sans-serif;
      width:390px;height:844px;overflow:hidden;display:flex;flex-direction:column}
    a{color:var(--lights)} a:hover{color:var(--lights-deep)}
    header{flex:none;padding:14px 16px 10px;border-bottom:2px solid var(--line);
      background:repeating-linear-gradient(90deg,transparent 0 46px,rgba(245,242,232,.03) 46px 48px),var(--field)}
    .brand{display:flex;align-items:baseline;gap:10px}
    .brand h1{font-family:'Oswald',sans-serif;font-weight:700;font-size:24px;letter-spacing:.06em;
      text-transform:uppercase;line-height:1}
    .brand h1 span{color:var(--lights)}
    .brand .inning{font-family:'Oswald',sans-serif;font-size:12px;font-weight:600;letter-spacing:.2em;
      color:var(--chalk-dim);text-transform:uppercase}
    .content{flex:1;min-height:0;overflow:hidden;padding:0 14px;display:flex;flex-direction:column}
    .eyebrow{display:flex;align-items:center;gap:10px;margin:14px 2px 8px;font-family:'Oswald',sans-serif;
      font-size:12px;font-weight:600;letter-spacing:.22em;text-transform:uppercase;color:var(--lights)}
    .eyebrow i{flex:1;height:1px;background:var(--line)}
    .card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
    .btn{display:flex;align-items:center;justify-content:center;min-height:48px;border-radius:10px;
      background:var(--lights);color:#1a1205;font-family:'Oswald',sans-serif;font-weight:700;font-size:15px;
      letter-spacing:.08em;text-transform:uppercase;border:none;width:100%}
    .btn.ghost{background:transparent;border:1.5px solid var(--line);color:var(--chalk)}
    .p{font-size:14px;line-height:1.5;color:var(--chalk);text-wrap:pretty}
    .dim{color:var(--chalk-dim)}
    .small{font-size:12px;line-height:1.5;color:var(--chalk-dim)}
    .tabbar{flex:none;display:flex;gap:2px;border-top:1px solid var(--line);background:rgba(9,22,15,.97);
      padding:7px 6px 12px}
    .tabbar a{flex:1;display:flex;flex-direction:column;align-items:center;gap:3px;padding:5px 0 3px;
      border-radius:10px;color:var(--chalk-dim);text-decoration:none;font-family:'Oswald',sans-serif;
      font-size:9.5px;font-weight:600;letter-spacing:.09em;text-transform:uppercase}
    .tabbar a svg{width:23px;height:23px;fill:none;stroke:currentColor;stroke-width:1.7;
      stroke-linecap:round;stroke-linejoin:round}
    .tabbar a.on{color:var(--lights)}
    .blocked{margin-top:auto;border:1.5px dashed var(--flag);border-radius:10px;padding:11px 13px;
      background:rgba(217,79,61,.07)}
    .blocked b{display:block;font-family:'Oswald',sans-serif;font-size:11px;font-weight:600;
      letter-spacing:.18em;text-transform:uppercase;color:var(--flag);margin-bottom:5px}
    .blocked p{font-size:12px;line-height:1.5;color:var(--chalk-dim)}
"""

ICONS = {
    "rounds": '<circle cx="12" cy="12" r="9"></circle><path d="M6.5 5.2c2 2.4 2.6 5.3 2 8.4M17.5 5.2c-2 2.4-2.6 5.3-2 8.4"></path>',
    "film": '<rect x="3" y="5" width="18" height="14" rx="2"></rect><path d="M3 9h18M3 15h18M8 5v14M16 5v14"></path>',
    "team": '<circle cx="9" cy="9" r="3"></circle><path d="M3.5 19c.6-3 2.8-4.5 5.5-4.5s4.9 1.5 5.5 4.5"></path><path d="M16 6.5a2.6 2.6 0 010 5M18 18.8c-.2-1.7-.8-3-1.8-3.9"></path>',
    "progress": '<path d="M4 19V5M4 19h16"></path><path d="M7.5 15.5l3.5-4 3 2.5L20 8"></path>',
    "you": '<circle cx="12" cy="8.5" r="3.5"></circle><path d="M5 19.5c.8-3.6 3.4-5.5 7-5.5s6.2 1.9 7 5.5"></path>',
}


def tabbar(active=None, tabs=("rounds", "film", "progress", "you")):
    """Parent shell tab bar. NOTE: the coach shell is Team/Progress/You only —
    a coach never gets a Film tab (R-03). Caught in review once already."""
    labels = {"rounds": "Rounds", "film": "Film", "team": "Team",
              "progress": "Progress", "you": "You"}
    out = ['<nav class="tabbar">']
    for t in tabs:
        cls = ' class="on"' if t == active else ""
        out.append(f'<a href="#"{cls}><svg viewBox="0 0 24 24">{ICONS[t]}</svg>{labels[t]}</a>')
    out.append("</nav>")
    return "\n".join(out)


def header(inning):
    return (f'<header><div class="brand"><h1>DUG<span>OUT</span></h1>'
            f'<div class="inning">{inning}</div></div></header>')


# ── the artboard template ────────────────────────────────────────────────────
ARTBOARD = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<!--
  SLOT {slot} · {title}
  Release {release} · Status {status}

  WHAT IT IS FOR
  {why}

  RULING
{ruling}

  CONSIDERED AND REJECTED
{rejected}
{warn}
  This drawing is the TARGET. Where it disagrees with what ships today, the
  contradiction is named above — the drawing is not a description of the build.
-->
<x-dc>
<helmet>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Oswald:wght@400;500;600;700&family=Inter:wght@400;500;600;700&display=swap">
  <style>{css}</style>
</helmet>
{body}
</x-dc>
</body>
</html>
"""


def indent(text, pad="    "):
    return "\n".join(pad + ln for ln in text.strip().split("\n"))


def emit(s):
    warn = ""
    if s.get("warn"):
        warn = "\n  ⚠ THE CODE CONTRADICTS THIS TODAY\n" + indent(s["warn"]) + "\n"
    return ARTBOARD.format(
        slot=s["slot"], title=s["title"], release=s["release"],
        status=s["status"], why=s["why"].strip(),
        ruling=indent(s["ruling"]), rejected=indent(s["rejected"]),
        warn=warn, css=BASE_CSS + s.get("css", ""), body=s["body"].strip(),
    )


# ═══════════════════════════════════════════════════════════════════════════
# THE MANIFEST — ordered. Insert in flow order; never append to the end.
# ═══════════════════════════════════════════════════════════════════════════

SCREENS = []

# ── PAGE 1 · PARENT (U1) ────────────────────────────────────────────────────

SCREENS.append(dict(
    slot="P-SPLASH", file="Splash.dc.html", page="page-1", title="Brand moment",
    release="R1", status="SHIPPED",
    why="The 1.2s hold that makes the app feel like a product rather than a web page.",
    ruling="""Min-hold 1200ms from page start, ruled 2026-07-25 in js/app.js:
"on fast boots the app is ready in <100ms and the splash was gone before a
single frame showed (see 'Splash Page.MP4', Jul 25)". Slow boots are
unaffected — they already exceed 1.2s.""",
    rejected="""No splash at all — rejected: the shell needs cover while the pose
bundles parse, and the brand moment is the only one a parent gets before
they are looking at their kid.""",
    body=f"""
<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px;
  background:radial-gradient(circle at 50% 38%, {T['field_2']} 0%, {T['field']} 62%)">
  <div style="font-family:'Oswald',sans-serif;font-weight:700;font-size:52px;letter-spacing:.06em;
    text-transform:uppercase;line-height:1">DUG<span style="color:{T['lights']}">OUT</span></div>
  <div style="width:74px;height:2px;background:{T['lights']};opacity:.8"></div>
  <div style="font-family:'Oswald',sans-serif;font-size:12.5px;font-weight:500;letter-spacing:.3em;
    text-transform:uppercase;color:{T['chalk_dim']}">One fix every round</div>
</div>
""",
))

SCREENS.append(dict(
    slot="P-WELCOME", file="Welcome.dc.html", page="page-1", title="First run",
    release="R1", status="DRAWN",
    why="The first screen a dad sees. It has to say what this is in one line he would repeat.",
    ruling="""Copy is the subtitle ruled in R-36 (2026-09-12): "one fix every round".
The promise is singular and forward-looking by design — R-02 forbids ever
showing a score, so the product must never open by implying a grade.""",
    rejected="""A feature list or a carousel — rejected: three screens of swiping before
the app does anything is how a cage-side download gets abandoned. One
sentence, one button.""",
    body=f"""
{header('Welcome')}
<div class="content">
  <div style="flex:1;display:flex;flex-direction:column;justify-content:center;gap:18px">
    <div style="font-family:'Oswald',sans-serif;font-size:30px;font-weight:600;line-height:1.15;
      letter-spacing:.02em;text-transform:uppercase">Film a round.<br>Fix one thing.<br>
      <span style="color:{T['lights']}">Swing again.</span></div>
    <p class="p">Prop your phone behind the plate. DugOut finds every swing, checks
      six things, and tells you the one to work on — in your coach's words.</p>
    <p class="small">Built for 8–17. The video stays on this phone.</p>
  </div>
  <div style="display:flex;flex-direction:column;gap:9px;padding-bottom:22px">
    <button class="btn">Get started</button>
    <button class="btn ghost">I already have an account</button>
  </div>
</div>
""",
))

SCREENS.append(dict(
    slot="P-ACCOUNT", file="Account.dc.html", page="page-1", title="Create the parent account",
    release="R1 local · R3 real", status="DRAWN",
    why="Establishes that an ADULT owns this account. Everything downstream depends on it.",
    ruling="""R1 is local-only — name + email on device, no server (R-27: no backend
before November). R3 adds Sign in with Apple, ruled as the only v1 identity:
no passwords, no reset emails, no credential store.
R-30 (2026-09-04): the self-serve 13–17 tier is DROPPED. Every account is
created by an adult. The Declared Age Range check at R3 stops here if the
account holder resolves to a minor.""",
    rejected="""Social logins beyond Apple — rejected under R-11 (no third-party SDKs).
A vendor SDK's behaviour becomes our COPPA violation; Apitor was fined for
exactly that in Sept 2025.""",
    body=f"""
{header('Step 1 of 4')}
<div class="content">
  <div class="eyebrow">Your account<i></i></div>
  <p class="p">DugOut accounts belong to a parent or guardian. You'll add your athlete next.</p>
  <div style="display:flex;flex-direction:column;gap:9px;margin-top:14px">
    <div class="card"><div class="small" style="margin-bottom:3px">Your name</div>
      <div style="font-size:15px">Derell Jenkins</div></div>
    <div class="card"><div class="small" style="margin-bottom:3px">Email</div>
      <div style="font-size:15px">derell@example.com</div></div>
  </div>
  <div style="margin-top:16px;display:flex;align-items:center;gap:10px;padding:11px 13px;
    border:1px solid {T['line']};border-radius:10px;background:{T['field_2']}">
    <svg viewBox="0 0 24 24" style="width:19px;height:19px;flex:none;fill:none;stroke:{T['chalk_dim']};stroke-width:1.7">
      <rect x="4" y="10" width="16" height="10" rx="2"></rect><path d="M8 10V7a4 4 0 018 0v3"></path></svg>
    <div class="small" style="flex:1">Stored on this phone only. Nothing is sent anywhere.</div>
  </div>
  <div style="margin-top:auto;padding-bottom:22px"><button class="btn">Continue</button></div>
</div>
""",
))

SCREENS.append(dict(
    slot="P-CONSENT", file="Consent.dc.html", page="page-1", title="Consent",
    release="R1", status="DRAWN · legally load-bearing",
    why="The COPPA-facing moment. Plain language, explicit affirmative action, timestamped.",
    ruling="""Four things must be on this screen and nothing may dilute them
(W1.1 step 3, and the COPPA memo): what is recorded · what happens to it ·
who can see it · how to undo all of it.
R-04: raw session video is deleted at segmentation and never leaves the
device. R-30 (2026-09-04): pose keypoints are BIOMETRIC under the 2025
amendments ("gait patterns"), so the notice must say so explicitly rather
than by implication.""",
    rejected="""A scroll-to-accept wall of legalese — rejected: it is the pattern every
regulator now treats as a dark pattern, and it buries the one fact that
actually sells this product to a parent (the video never leaves the phone).""",
    body=f"""
{header('Step 2 of 4')}
<div class="content">
  <div class="eyebrow">Before you record<i></i></div>
  <div style="display:flex;flex-direction:column;gap:8px">
    <div class="card"><div style="font-family:'Oswald',sans-serif;font-size:12px;font-weight:600;
      letter-spacing:.16em;text-transform:uppercase;color:{T['lights']};margin-bottom:5px">What we record</div>
      <p class="small">Video of your athlete swinging, while you're recording. Nothing else, never in the background.</p></div>
    <div class="card"><div style="font-family:'Oswald',sans-serif;font-size:12px;font-weight:600;
      letter-spacing:.16em;text-transform:uppercase;color:{T['lights']};margin-bottom:5px">What happens to it</div>
      <p class="small">The full recording is <b style="color:{T['chalk']}">deleted</b> as soon as we cut it into
      swings. Only the swing clips are kept, and they stay on this phone. To find the swings we read body position — the kind of data the law
      calls <b style="color:{T['chalk']}">biometric</b>. It is read on this phone, used, and thrown
      away: never stored, never logged, never sent anywhere.</p></div>
    <div class="card"><div style="font-family:'Oswald',sans-serif;font-size:12px;font-weight:600;
      letter-spacing:.16em;text-transform:uppercase;color:{T['lights']};margin-bottom:5px">Who can see it</div>
      <p class="small">Nobody, until you invite them. A coach you approve sees pass/fail marks — never your video.</p></div>
    <div class="card"><div style="font-family:'Oswald',sans-serif;font-size:12px;font-weight:600;
      letter-spacing:.16em;text-transform:uppercase;color:{T['lights']};margin-bottom:5px">How to undo it</div>
      <p class="small">Delete a clip, a round, a profile, or the whole account — any time, from You.</p></div>
  </div>
  <div style="margin-top:auto;padding-bottom:22px;display:flex;flex-direction:column;gap:8px">
    <button class="btn">I agree — I'm the parent</button>
    <p class="small" style="text-align:center">Recorded with today's date. Full privacy policy in You → Legal.</p>
  </div>
</div>
""",
))

SCREENS.append(dict(
    slot="P-PROFILE-NEW", file="ProfileNew.dc.html", page="page-1", title="First athlete profile",
    release="R1", status="DRAWN",
    why="Creates the atomic unit of the whole product: the parent-owned athlete profile.",
    ruling="""The athlete profile is the atomic unit and it is PARENT-OWNED. A coach
never creates or owns child data — he is granted a results-only view and the
parent revokes it without asking anyone. This is the GameChanger precedent,
the COPPA answer, and a marketed trust feature at once.
Birth month/year drives the LTAD age band, which sets the rails: 7–10
environmental/fun-first · 12–14 mechanical adjustments unlocked · 14–16
growth-spurt caution · no weighted implements under 13.""",
    rejected="""Full date of birth — rejected: month and year are enough to band the
athlete, and collecting less of a child's data is the whole posture.
Cap of 2 profiles per account, from the pricing model.""",
    body=f"""
{header('Step 3 of 4')}
<div class="content">
  <div class="eyebrow">Your athlete<i></i></div>
  <div style="display:flex;flex-direction:column;gap:9px">
    <div class="card"><div class="small" style="margin-bottom:3px">First name</div>
      <div style="font-size:15px">Elijah</div></div>
    <div style="display:flex;gap:9px">
      <div class="card" style="flex:1"><div class="small" style="margin-bottom:3px">Born</div>
        <div style="font-size:15px">March 2015</div></div>
      <div class="card" style="flex:1"><div class="small" style="margin-bottom:3px">Bats</div>
        <div style="font-size:15px">Right</div></div>
    </div>
    <div class="card"><div class="small" style="margin-bottom:6px">Sport</div>
      <div style="display:flex;gap:7px">
        <div style="flex:1;text-align:center;padding:9px;border-radius:8px;background:{T['lights']};
          color:#1a1205;font-family:'Oswald',sans-serif;font-size:13px;font-weight:600;letter-spacing:.06em;
          text-transform:uppercase">Baseball</div>
        <div style="flex:1;text-align:center;padding:9px;border-radius:8px;border:1px solid {T['line']};
          font-family:'Oswald',sans-serif;font-size:13px;font-weight:600;letter-spacing:.06em;
          text-transform:uppercase;color:{T['chalk_dim']}">Softball</div>
      </div></div>
  </div>
  <div style="margin-top:13px;padding:11px 13px;border-radius:10px;background:{T['field_2']};
    border-left:2px solid {T['lights']}">
    <div class="small"><b style="color:{T['chalk']}">11u band.</b> Cues stay environmental — what to feel,
    not what to move. Mechanical adjustments unlock at 12, weighted implements at 13.</div>
  </div>
  <div style="margin-top:auto;padding-bottom:22px"><button class="btn">Continue</button></div>
</div>
""",
))

SCREENS.append(dict(
    slot="P-PHILOSOPHY-PICK", file="PhilosophyPick.dc.html", page="page-1",
    title="Pick a coaching voice", release="R1", status="DRAWN",
    why="Sets the VOICE of every piece of feedback. Five taps, reversible, never changes what we look for.",
    ruling="""R1 is preset SELECTION only — four schools, no authoring:
Rotational (Williams) · Linear weight-shift (Lau) · Modern constraint-led
(Driveline) · Contact-first youth (USA Baseball LTAD).
The line under it is load-bearing and must survive copy edits: changing the
philosophy changes HOW feedback is worded, never WHAT we look for. Substance
comes from the vetted library (R-06); voice comes from the coach.""",
    rejected="""Letting a parent write their own cues at R1 — rejected under R-05 and
R-29: philosophy is selection, never authoring. An unvetted cue typed by a
parent is exactly the hallucinated-coaching failure the closed library exists
to prevent.""",
    body=f"""
{header('Step 4 of 4')}
<div class="content">
  <div class="eyebrow">How should corrections sound?<i></i></div>
  <p class="small">This only sets the wording. What we check never changes.</p>
  <div style="display:flex;flex-direction:column;gap:8px;margin-top:11px">
    <div style="border:1.5px solid {T['lights']};background:{T['field_2']};border-radius:10px;padding:11px 13px">
      <div style="font-family:'Oswald',sans-serif;font-size:14.5px;font-weight:600;letter-spacing:.05em;
        text-transform:uppercase;color:{T['lights']}">Contact first</div>
      <div class="small" style="margin-top:3px">Youth-development standard. Put it in play, hard.</div></div>
    <div class="card"><div style="font-family:'Oswald',sans-serif;font-size:14.5px;font-weight:600;
      letter-spacing:.05em;text-transform:uppercase">Rotational</div>
      <div class="small" style="margin-top:3px">Hips lead, stay inside the ball. The Williams school.</div></div>
    <div class="card"><div style="font-family:'Oswald',sans-serif;font-size:14.5px;font-weight:600;
      letter-spacing:.05em;text-transform:uppercase">Weight shift</div>
      <div class="small" style="margin-top:3px">Load back, drive through. The Lau school.</div></div>
    <div class="card"><div style="font-family:'Oswald',sans-serif;font-size:14.5px;font-weight:600;
      letter-spacing:.05em;text-transform:uppercase">Constraint-led</div>
      <div class="small" style="margin-top:3px">Change the drill, let the swing solve it.</div></div>
  </div>
  <div style="margin-top:auto;padding-bottom:22px;display:flex;flex-direction:column;gap:8px">
    <button class="btn">Start hitting</button>
    <p class="small" style="text-align:center">Change it any time in You → Coaching voice.</p>
  </div>
</div>
""",
))

SCREENS.append(dict(
    slot="P-ROUNDS-EMPTY", file="RoundsEmpty.dc.html", page="page-1",
    title="Rounds — empty state", release="R1", status="DRAWN",
    why="The screen a new user lands on. It has one job: get the phone on a tripod.",
    ruling="""Copy ruled in W1.1 step 7: "Prop your phone up behind the plate and hit."
The empty state instructs the physical setup, because the product's accuracy
depends on a fixed camera — R-25's whole cascade assumes a tripod and a
per-session background model.""",
    rejected="""A sample round with fake data to "show what you'll get" — rejected under
the no-fabricated-numbers rule. A demo round a parent could mistake for their
kid's is worse than an empty screen.""",
    body=f"""
{header('Rounds')}
<div class="content">
  <div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;
    gap:16px;text-align:center;padding:0 12px">
    <svg viewBox="0 0 24 24" style="width:54px;height:54px;fill:none;stroke:{T['line']};stroke-width:1.4">
      <rect x="6" y="2.5" width="12" height="19" rx="2"></rect><circle cx="12" cy="9" r="2.4"></circle>
      <path d="M12 14v5M9 21.5h6"></path></svg>
    <div style="font-family:'Oswald',sans-serif;font-size:19px;font-weight:600;letter-spacing:.04em;
      text-transform:uppercase;line-height:1.3">Prop your phone up<br>behind the plate and hit</div>
    <p class="small" style="max-width:250px">Side view, full body in frame, bat visible at the top of the
      load. Ninety seconds is about fifteen swings.</p>
  </div>
  <div style="padding-bottom:18px;display:flex;flex-direction:column;gap:8px">
    <button class="btn">Start a round</button>
    <button class="btn ghost">Add footage you already have</button>
  </div>
</div>
{tabbar('rounds')}
""",
))

SCREENS.append(dict(
    slot="P-CAGE", file="Cage.dc.html", page="page-1", title="Recording",
    release="R1", status="DRAWN",
    why="Ninety seconds against a tripod. Nothing on screen may need a tap while hitting.",
    ruling="""Screen stays awake, big timer, auto-stop at the cap (W1.2 Path A).
No fake iOS status bar is drawn — the real one renders on top, and a painted
one reads as doubled up.
The between-swings feedback line belongs to R4 (DUG-50), not here. True
in-swing feedback is IMPOSSIBLE for anyone: the swing is 130–280ms and hosted
models sample video at a fixed 1 FPS (R-25). Do not draw it as if it were
close.""",
    rejected="""A live skeleton overlay during capture — rejected: it costs battery and
frame rate during the one moment accuracy matters, and it invites the
metrics-firehose comparison the product is positioned against.""",
    body=f"""
<div style="flex:1;position:relative;background:linear-gradient(170deg,#16301f 0%,{T['field']} 70%);
  display:flex;flex-direction:column">
  <div style="position:absolute;inset:26px 20px auto 20px;border:1.5px dashed rgba(245,242,232,.22);
    border-radius:6px;height:520px"></div>
  <div style="position:absolute;top:300px;left:0;right:0;text-align:center;
    font-family:'Oswald',sans-serif;font-size:11.5px;letter-spacing:.22em;text-transform:uppercase;
    color:rgba(245,242,232,.4)">Keep the whole body in frame</div>
  <div style="margin-top:auto;padding:0 20px 26px;display:flex;flex-direction:column;align-items:center;gap:14px">
    <div style="font-family:'Oswald',sans-serif;font-size:62px;font-weight:700;line-height:1;
      font-variant-numeric:tabular-nums;color:{T['lights']}">0:47</div>
    <div style="width:100%;height:5px;border-radius:3px;background:rgba(245,242,232,.14);overflow:hidden">
      <div style="width:48%;height:100%;background:{T['lights']}"></div></div>
    <div class="small" style="letter-spacing:.14em;text-transform:uppercase;font-family:'Oswald',sans-serif">
      Recording · 90 second round</div>
    <button class="btn ghost" style="width:150px;min-height:44px">Stop</button>
  </div>
</div>
""",
))

SCREENS.append(dict(
    slot="P-SEGMENTING", file="Segmenting.dc.html", page="page-1",
    title="Finding your swings", release="R1", status="DRAWN · data caveat",
    why="The moment raw video is destroyed. Say so here, because it is the promise being kept.",
    ruling="""Real progress, not an indeterminate spinner (W1.2 step 4) — this step
takes long enough that a fake spinner reads as a hang.
R-04 is executed at this exact moment: the full recording is deleted once it
is cut into swings. Telling the user AS IT HAPPENS is worth more than the
same sentence in a privacy policy nobody opens.""",
    rejected="""Running segmentation silently in the background and surfacing only the
result — rejected: the deletion is the product's central promise and this is
the only honest moment to show it happening.""",
    warn="""js/segment.js + js/config.js — the swing count this screen reports is
governed by SPIKE_ENTER_MULT, which was 3.0 and returned ZERO swings on both
ground-truth clips. Changed to 2.4 in 3b7fae6 (2026-09-08); CANON R-14 has the
diagnosis RESOLVED and the VALUE still PROVISIONAL, because the four stable
runs behind 2.4 are headless on a VP9 remux and motion energy IS inter-frame
delta. No number on this screen is trustworthy until a device run on original
H.264 across all five pitch_0*.mov clips.""",
    body=f"""
{header('Round')}
<div class="content">
  <div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px">
    <div style="font-family:'Oswald',sans-serif;font-size:22px;font-weight:600;letter-spacing:.05em;
      text-transform:uppercase">Finding your swings</div>
    <div style="width:100%;height:6px;border-radius:3px;background:{T['line']};overflow:hidden">
      <div style="width:66%;height:100%;background:{T['lights']}"></div></div>
    <div class="small">Checking 90 seconds of footage</div>
    <div style="margin-top:12px;display:flex;align-items:center;gap:9px;padding:11px 13px;border-radius:10px;
      background:{T['field_2']};border:1px solid {T['line']}">
      <svg viewBox="0 0 24 24" style="width:18px;height:18px;flex:none;fill:none;stroke:{T['pass']};stroke-width:2">
        <path d="M4 12.5l5 5L20 6.5"></path></svg>
      <div class="small" style="flex:1">Full recording deleted. Only the swings are kept.</div>
    </div>
  </div>
</div>
""",
))

# ── RULE 1 IN ACTION ────────────────────────────────────────────────────────
# P-ROUND-START belongs between P-ROUNDS-EMPTY and P-CAGE. It is INSERTED at
# its flow position, not appended — appending would put "choose your round
# length" after "recording", and the sheet would stop telling the story.
SCREENS.insert(7, dict(
    slot="P-ROUND-START", file="RoundStart.dc.html", page="page-1",
    title="Set up the round", release="R1", status="DRAWN",
    why="The last screen before the phone goes on the tripod. Length, athlete, framing.",
    ruling="""60s or 90s only (W1.2). 90s is ~15 swings against a JUGS carousel
feeding every ~6s — the cadence prior R-25 relies on to reconcile candidates.
Profile picker appears only when the account has more than one athlete.""",
    rejected="""An open-ended record-until-you-stop mode — rejected: an unbounded clip
breaks the per-session background model and the cadence prior, and it is how
you end up processing eleven minutes of a kid's little brother.""",
    body=f"""
{header('New round')}
<div class="content">
  <div class="eyebrow">Who's hitting<i></i></div>
  <div style="display:flex;gap:8px">
    <div style="flex:1;border:1.5px solid {T['lights']};background:{T['field_2']};border-radius:10px;
      padding:11px 13px;font-family:'Oswald',sans-serif;font-size:15px;font-weight:600;letter-spacing:.05em;
      text-transform:uppercase;color:{T['lights']}">Elijah <span style="font-family:'Inter';font-size:11px;
      font-weight:400;letter-spacing:0;text-transform:none;color:{T['chalk_dim']}">11u</span></div>
    <div style="flex:1;border:1px solid {T['line']};border-radius:10px;padding:11px 13px;
      font-family:'Oswald',sans-serif;font-size:15px;font-weight:600;letter-spacing:.05em;
      text-transform:uppercase;color:{T['chalk_dim']}">Mya <span style="font-family:'Inter';font-size:11px;
      font-weight:400;letter-spacing:0;text-transform:none">9u</span></div>
  </div>
  <div class="eyebrow">How long<i></i></div>
  <div style="display:flex;gap:8px">
    <div style="flex:1;text-align:center;border:1px solid {T['line']};border-radius:10px;padding:13px">
      <div style="font-family:'Oswald',sans-serif;font-size:26px;font-weight:700;line-height:1;
        color:{T['chalk_dim']}">60s</div>
      <div class="small" style="margin-top:4px">~10 swings</div></div>
    <div style="flex:1;text-align:center;border:1.5px solid {T['lights']};background:{T['field_2']};
      border-radius:10px;padding:13px">
      <div style="font-family:'Oswald',sans-serif;font-size:26px;font-weight:700;line-height:1;
        color:{T['lights']}">90s</div>
      <div class="small" style="margin-top:4px">~15 swings</div></div>
  </div>
  <div class="eyebrow">Before you start<i></i></div>
  <div class="card"><div class="small" style="line-height:1.65">
    Phone on a tripod, side view · full body in frame · bat visible at the top of the load ·
    don't move the phone once the round starts</div></div>
  <div style="margin-top:auto;padding-bottom:22px"><button class="btn">3 · 2 · 1 · Go</button></div>
</div>
""",
))

SCREENS.append(dict(
    slot="P-ROUND", file="Main.dc.html", page="page-1", title="The Round Card",
    release="R1", status="DRAWN · the product",
    why="The fifteen seconds of reading that the whole product exists to produce.",
    ruling="""The order is ruled and is not a layout preference (W1.3):
  1. priority focus, FIRST AND BIGGEST, one thing, in the philosophy's voice
  2. the drill underneath it, with its ladder position for the age band
  3. six checkpoints as PASS/FAIL marks
  4. per-checkpoint trend
  5. the swing reel
R-02: the internal score is NEVER shown — not here, not in a tooltip, not in
a debug view. PASS/FAIL is the entire user-visible vocabulary.
ER-03: never name a fault from one batted-ball result. Faults come from
patterns across the session's swings. One swing means say less.""",
    rejected="""Showing all six faults at once — rejected: it is the metrics firehose every
competitor ships and the market's stated complaint ("gadgets are not hitting
coaches"). One fix, in his coach's words, is the entire wedge.
A numeric score out of 100 — rejected permanently under R-02.""",
    warn="""js/segment.js + js/config.js — CONTACT_ANCHOR is 0.62 by design but contact
actually lands at 0.500 / 0.761 / 0.572 depending on audio confirmation
(CANON R-15, DUG-54). Every checkpoint below is currently registered against
the wrong frames, and the error FLIPS DIRECTION with audio confirmation, so a
whiff and a solid contact in one round are oppositely mis-registered. The six
marks drawn here are the target; today they are plausible and wrong.""",
    body=f"""
{header('Round · 12 swings')}
<div class="content">
  <div class="eyebrow">Work on this<i></i></div>
  <div style="border:1.5px solid {T['lights']};background:{T['field_2']};border-radius:12px;padding:13px 15px">
    <div style="font-size:17px;line-height:1.4;text-wrap:pretty">Let the barrel find the ball out front —
      think about driving it back through the pitcher, not down at it.</div>
    <div style="margin-top:11px;padding-top:10px;border-top:1px solid {T['line']};display:flex;
      align-items:center;gap:9px">
      <div style="font-family:'Oswald',sans-serif;font-size:10.5px;font-weight:600;letter-spacing:.18em;
        text-transform:uppercase;color:{T['lights']}">Drill</div>
      <div style="font-size:13.5px;flex:1">High tee, out front · 2 rounds of 10</div>
    </div>
  </div>
  <div class="eyebrow">This round<i></i></div>
  <div style="display:flex;flex-direction:column;gap:4px">
""" + "".join(
        f"""    <div style="display:grid;grid-template-columns:1fr auto auto;align-items:center;gap:10px;
      background:{T['card']};border:1px solid {T['line']};border-radius:8px;padding:8px 12px">
      <div style="font-family:'Oswald',sans-serif;font-size:13.5px;font-weight:600;letter-spacing:.06em;
        text-transform:uppercase">{name}</div>
      <div class="small" style="font-size:11px">{trend}</div>
      <div style="font-family:'Oswald',sans-serif;font-size:11px;font-weight:700;letter-spacing:.1em;
        color:{T['pass'] if ok else T['flag']}">{'PASS' if ok else 'WORK'}</div>
    </div>
""" for name, ok, trend in [
            ("Stance", True, "passed 6 straight"), ("Load", True, "passed 5 straight"),
            ("Stride", True, "passed 2 straight"), ("Hips fire", True, "passed 6 straight"),
            ("Contact", False, "3rd round in a row"), ("Finish", True, "passed 6 straight")]
    ) + f"""
  </div>
  <div class="eyebrow">Swing reel · all 12<i></i></div>
  <div style="display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:6px">
""" + "".join(
        f"""    <div style="height:72px;border-radius:7px;background:{T['field_2']};
      border:1px solid {T['line']};position:relative">
      <div style="position:absolute;left:5px;bottom:5px;width:7px;height:7px;border-radius:2px;
        background:{T['pass'] if ok else T['flag']}"></div>
      <div style="position:absolute;right:5px;top:4px;font-family:'Oswald',sans-serif;font-size:10px;
        color:{T['chalk_dim']}">{i}</div></div>
""" for i, ok in enumerate(
            [True, True, False, True, False, True, True, False, True, True, False, True], start=1)
    ) + f"""
  </div>
  <div class="small" style="margin-top:9px;text-align:center">Red marks the swings Contact failed on.
    Tap any swing to scrub it.</div>
</div>
{tabbar('rounds')}
""",
))

SCREENS.append(dict(
    slot="P-CHECKPOINT", file="Checkpoint.dc.html", page="page-1",
    title="Checkpoint drill-in", release="R1", status="SHIPPED",
    why="Tapping a mark. Why it failed, what to do, and the swings it failed on.",
    ruling="""Shipped in c4d1b6f (2026-07-25). Still PASS/FAIL only at every depth
(R-02) — drilling in gets you EVIDENCE, never a score. The tips shown are
selected from the closed library (R-06); the app never writes one.""",
    rejected="""A confidence percentage on the fault — rejected: it is an internal score
wearing a different hat, and it crosses the R-02 line.""",
    body=f"""
{header('Contact')}
<div class="content">
  <div style="display:flex;align-items:baseline;gap:10px;margin-top:14px">
    <div style="font-family:'Oswald',sans-serif;font-size:26px;font-weight:700;letter-spacing:.04em;
      text-transform:uppercase">Contact</div>
    <div style="font-family:'Oswald',sans-serif;font-size:12px;font-weight:700;letter-spacing:.1em;
      color:{T['flag']}">WORK</div>
  </div>
  <p class="p" style="margin-top:9px">The barrel is arriving late and the ball is getting deep.
    Four of twelve swings showed it.</p>
  <div class="eyebrow">What to do<i></i></div>
  <div class="card"><div style="font-size:14.5px;line-height:1.45">Move the tee two inches out front
    and a ball-width closer. Hit it back up the middle.</div>
    <div class="small" style="margin-top:7px">High tee · 2 rounds of 10 · from the vetted library</div></div>
  <div class="eyebrow">The swings it showed up on<i></i></div>
  <div style="display:flex;gap:5px">
""" + "".join(
        f"""    <div style="flex:none;width:52px;height:66px;border-radius:7px;background:{T['field_2']};
      border:1.5px solid {T['flag']};position:relative">
      <div style="position:absolute;right:5px;top:4px;font-family:'Oswald',sans-serif;font-size:10px;
        color:{T['chalk_dim']}">{i}</div></div>
""" for i in (3, 5, 8, 11)
    ) + f"""
  </div>
  <div style="margin-top:13px;padding:10px 12px;border-radius:9px;background:{T['field_2']};
    border-left:2px solid {T['line']}">
    <div class="small">One swing never names a fault. This is a pattern across the round.</div></div>
</div>
{tabbar('rounds')}
""",
))

SCREENS.append(dict(
    slot="P-REEL", file="Reel.dc.html", page="page-1", title="Film space",
    release="R1", status="SHIPPED",
    why="Every swing from the round, scrubbable, with the shadow-swing compare.",
    ruling="""Shipped as Film Space v2 in 565ba95 (DUG-39/40). Per-swing fault marks
persist per swing (DUG-42) so the viewer can flag the exact checkpoint that
failed on THAT swing rather than only the round-level rollup.
Naming note (R-32, 2026-09-10): "Film Room" is GameChanger's feature name —
6M+ users, DICK'S-owned. Internal file names (filmroom.js, filmshell.js) are
unaffected, but NO customer-facing copy uses "film room" as a product noun.""",
    rejected="""Letting a parent export or share a raw clip — rejected under R-03/R-04.
There is no share affordance here on purpose; the clip cannot leave.""",
    body=f"""
{header('Film')}
<div style="flex:none;height:300px;background:linear-gradient(165deg,#16301f,{T['field']});
  border-bottom:1px solid {T['line']};position:relative;display:flex;align-items:center;justify-content:center">
  <div style="font-family:'Oswald',sans-serif;font-size:11px;letter-spacing:.2em;text-transform:uppercase;
    color:rgba(245,242,232,.3)">Swing 3 · 0.24s</div>
  <div style="position:absolute;left:14px;right:14px;bottom:14px;height:4px;border-radius:2px;
    background:rgba(245,242,232,.16)"><div style="width:38%;height:100%;border-radius:2px;
    background:{T['lights']}"></div></div>
</div>
<div class="content">
  <div style="display:flex;gap:7px;margin-top:12px">
    <div style="flex:1;text-align:center;padding:9px;border-radius:8px;border:1px solid {T['line']};
      font-family:'Oswald',sans-serif;font-size:11.5px;letter-spacing:.1em;text-transform:uppercase;
      color:{T['chalk_dim']}">0.25×</div>
    <div style="flex:1;text-align:center;padding:9px;border-radius:8px;background:{T['lights']};color:#1a1205;
      font-family:'Oswald',sans-serif;font-size:11.5px;letter-spacing:.1em;text-transform:uppercase">Compare</div>
    <div style="flex:1;text-align:center;padding:9px;border-radius:8px;border:1px solid {T['line']};
      font-family:'Oswald',sans-serif;font-size:11.5px;letter-spacing:.1em;text-transform:uppercase;
      color:{T['chalk_dim']}">Frames</div>
  </div>
  <div class="eyebrow">This round · all 12<i></i></div>
  <div style="display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:6px">
""" + "".join(
        f"""    <div style="height:70px;border-radius:7px;background:{T['field_2']};
      border:{'1.5px solid ' + T['lights'] if i == 3 else '1px solid ' + T['line']};position:relative">
      <div style="position:absolute;left:5px;bottom:5px;width:7px;height:7px;border-radius:2px;
        background:{T['pass'] if ok else T['flag']}"></div>
      <div style="position:absolute;right:5px;top:4px;font-family:'Oswald',sans-serif;font-size:10px;
        color:{T['chalk_dim']}">{i}</div></div>
""" for i, ok in [(1, True), (2, True), (3, False), (4, True), (5, False), (6, True), (7, True), (8, False),
                  (9, True), (10, True), (11, False), (12, True)]
    ) + f"""
  </div>
</div>
{tabbar('film')}
""",
))

SCREENS.append(dict(
    slot="P-CELEBRATE", file="Celebrate.dc.html", page="page-1",
    title="All six pass", release="R1", status="DRAWN",
    why="The retention moment. The only screen in the product allowed to be loud.",
    ruling="""W1.3 step 6: all six pass earns a celebration, confetti-grade. This is
the moment a kid shows his dad the phone, and it is the single strongest
reason he asks to record again next week.
Still no score (R-02) — the celebration is for the SIX MARKS, not a number.""",
    rejected="""Celebrating a PERSONAL BEST — rejected: a "best" ranks a kid against his
own history and invites the leaderboard this product exists to avoid. Six
passes is a fact about this round and nothing else.
(Streaks are fine and have their own screen, A-STREAKS — a streak is a count
of consecutive passes, not a comparison. An earlier draft of this rejection
barred streaks too and contradicted that screen; corrected 2026-09-13.)""",
    body=f"""
<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:20px;
  padding:0 26px;text-align:center;background:radial-gradient(circle at 50% 40%,{T['field_2']} 0%,{T['field']} 66%)">
  <div style="display:flex;gap:7px">
""" + "".join(
        f"""    <div style="width:26px;height:34px;border-radius:4px;background:{T['pass']}"></div>
""" for _ in range(6)
    ) + f"""
  </div>
  <div style="font-family:'Oswald',sans-serif;font-size:34px;font-weight:700;letter-spacing:.04em;
    text-transform:uppercase;line-height:1.1">All six<br>clean</div>
  <p class="p">Every checkpoint passed this round. Stance through finish.</p>
  <div style="width:100%;display:flex;flex-direction:column;gap:8px;margin-top:6px">
    <button class="btn">Show Elijah</button>
    <button class="btn ghost">Back to the round</button>
  </div>
</div>
""",
))

SCREENS.append(dict(
    slot="P-PROGRESS", file="Progress.dc.html", page="page-1", title="Progress",
    release="R1", status="DRAWN · renders no computed figure",
    why="Weeks, not rounds. The reason a subscription renews.",
    ruling="""W1.4: per-checkpoint pass-rate over recent sessions, streaks, session
count and cadence, priority-focus history.
NEVER a number, never a grade, never a percentile against other kids. Trend
is shown as marks over time — pass/fail per round — because that is the only
representation that does not smuggle a score back in through a chart axis.""",
    rejected="""A percentage per checkpoint ("Contact 67%") — rejected under R-02: a
percentage IS a score. It is also the exact comparison that turns a kid's
practice into a ranking.""",
    warn="""No athlete has enough recorded history for these trends to be real. The
SHAPE is drawn; every mark here is illustrative and the screen says so. When
this ships it must render only what the profile actually contains — a profile
with two rounds shows two rounds, not a smoothed line implying more.""",
    body=f"""
{header('Progress · Elijah')}
<div class="content">
  <div class="eyebrow">Last 6 rounds<i></i></div>
  <div style="display:flex;flex-direction:column;gap:5px">
""" + "".join(
        f"""    <div style="display:grid;grid-template-columns:84px 1fr;align-items:center;gap:10px">
      <div style="font-family:'Oswald',sans-serif;font-size:12px;font-weight:600;letter-spacing:.06em;
        text-transform:uppercase;color:{T['chalk_dim']}">{name}</div>
      <div style="display:flex;gap:4px">""" + "".join(
            f"""<div style="flex:1;height:19px;border-radius:3px;background:{T['pass'] if m else T['flag']}"></div>"""
            for m in marks) + """</div>
    </div>
""" for name, marks in [
            ("Stance", [1, 1, 1, 1, 1, 1]), ("Load", [0, 1, 1, 1, 1, 1]),
            ("Stride", [0, 0, 1, 0, 1, 1]), ("Hips fire", [1, 1, 1, 1, 1, 1]),
            ("Contact", [1, 0, 0, 1, 0, 0]), ("Finish", [1, 1, 1, 1, 1, 1])]
    ) + f"""
  </div>
  <div class="eyebrow">What he's been working on<i></i></div>
  <div style="display:flex;flex-direction:column;gap:6px">
    <div class="card" style="padding:10px 13px"><div style="font-size:13.5px">Stride was the focus
      three rounds ago</div><div class="small" style="margin-top:2px">Passed twice since</div></div>
    <div class="card" style="padding:10px 13px"><div style="font-size:13.5px">Contact is the focus now</div>
      <div class="small" style="margin-top:2px">Third round running</div></div>
  </div>
  <div class="blocked"><b>Illustrative — not computed</b>
    <p>No profile has this much history yet. This screen renders only the rounds a profile
    actually contains; it never smooths, never extrapolates, and never shows a percentage.</p></div>
</div>
{tabbar('progress')}
""",
))

SCREENS.append(dict(
    slot="P-YOU", file="You.dc.html", page="page-1", title="You",
    release="R1", status="DRAWN",
    why="Account, athletes, coaching voice, storage, and the exits Apple requires.",
    ruling="""Structure follows the GameChanger account pattern Derell recorded as a
reference (Account Settings.MP4, 26 Jul): profile header → athletes →
subscription → settings → legal → delete → restore purchases → sign out with
a version footer. Subscription management DEFERS to Apple's native sheet
rather than being reimplemented.
R-33 (2026-09-12): the home-screen name stays DugOut regardless of the store
listing title. This screen is where the product refers to itself.""",
    rejected="""Burying Delete account inside a submenu — rejected: App Review 5.1.1(v)
requires it reachable in-app, and it sits FLAT in the list, destructive-styled.""",
    warn="""The August mockup of this screen rendered "Player · $99/yr" and a renewal
date while DUG-25 had ruled no pricing at all — logged as CANON R-16. R-26
has since ruled $99/yr, but it is RULED AND NOT PUBLISHABLE until StoreKit
charges it. This drawing therefore shows the subscription row WITHOUT a price.
That is deliberate: it is the rule working, not an omission.""",
    body=f"""
{header('You')}
<div class="content">
  <div style="display:flex;align-items:center;gap:13px;background:{T['card']};border:1px solid {T['line']};
    border-radius:12px;padding:11px 13px;margin-top:12px">
    <div style="width:40px;height:40px;border-radius:12px;background:{T['field_2']};border:1.5px solid {T['line']};
      display:flex;align-items:center;justify-content:center;font-family:'Oswald',sans-serif;font-weight:700;
      font-size:15px;color:{T['chalk_dim']}">DJ</div>
    <div><b style="font-family:'Oswald',sans-serif;font-size:16px;font-weight:600;letter-spacing:.05em;
      display:block">Derell Jenkins</b>
      <small class="small">derell@example.com · Parent</small></div>
  </div>
  <div class="eyebrow">Athletes<i></i></div>
  <div style="display:flex;flex-direction:column;gap:5px">
    <div class="card" style="padding:9px 13px"><div style="font-family:'Oswald',sans-serif;font-size:15px;
      letter-spacing:.06em;text-transform:uppercase">Elijah</div>
      <div class="small">11u · Coach Mike White can see results</div></div>
    <div class="card" style="padding:9px 13px"><div style="font-family:'Oswald',sans-serif;font-size:15px;
      letter-spacing:.06em;text-transform:uppercase">Mya</div>
      <div class="small">9u · Private — no coach linked</div></div>
  </div>
  <div class="eyebrow">Settings<i></i></div>
  <div style="display:flex;flex-direction:column;gap:5px">
    <div class="card" style="padding:9px 13px;display:grid;grid-template-columns:1fr auto;gap:10px">
      <div><div style="font-size:13.5px">Subscription</div>
        <div class="small">Managed through Apple</div></div>
      <div class="small" style="font-family:'Oswald',sans-serif;letter-spacing:.08em;
        text-transform:uppercase">Manage</div></div>
    <div class="card" style="padding:9px 13px;display:grid;grid-template-columns:1fr auto;gap:10px">
      <div><div style="font-size:13.5px">Coaching voice</div>
        <div class="small">Home rounds use Coach Mike's</div></div><div class="small">›</div></div>
    <div class="card" style="padding:9px 13px;display:grid;grid-template-columns:1fr auto;gap:10px">
      <div><div style="font-size:13.5px">Storage</div>
        <div class="small">168 clips on this phone</div></div>
      <div class="small" style="font-family:'Oswald',sans-serif;letter-spacing:.08em;
        text-transform:uppercase">Manage</div></div>
    <div class="card" style="padding:9px 13px;display:grid;grid-template-columns:1fr auto;gap:10px">
      <div style="font-size:13.5px">Help, privacy &amp; terms</div><div class="small">›</div></div>
    <div class="card" style="padding:9px 13px;display:grid;grid-template-columns:1fr auto;gap:10px">
      <div style="font-size:13.5px">Restore purchases</div><div class="small">›</div></div>
    <div class="card" style="padding:9px 13px;border-color:rgba(217,79,61,.5);display:grid;
      grid-template-columns:1fr auto;gap:10px">
      <div><div style="font-size:13.5px;color:{T['flag']}">Delete account</div>
        <div class="small">Your account, both athletes, every clip</div></div><div class="small">›</div></div>
  </div>
</div>
{tabbar('you')}
""",
))

SCREENS.append(dict(
    slot="P-LINK-COACH", file="LinkCoach.dc.html", page="page-1",
    title="Approve a coach", release="R4", status="DRAWN",
    why="The parent grants results-only visibility. The screen that has to be unambiguous.",
    ruling="""The approval copy is ruled verbatim in W1.5 and the emphasis is not
decorative: the coach sees the same results the parent sees — pass/fail
marks, priority focus, swing reel — for every round INCLUDING ones recorded
at home, and he can NOT see or download raw video.
Approval is PER PROFILE, never account-wide. On acceptance the profile's
philosophy defaults to the coach's; the parent can switch it back for home
sessions PRIVATELY, with no notification to the coach.""",
    rejected="""Account-wide approval with a per-profile opt-out — rejected: the default
must be the narrower grant. A sibling on another team is the common case,
not the edge case.""",
    warn="""THE SOURCE SPEC CONTRADICTS ITSELF, on the most legally load-bearing grant
in the product. W1.5's approval copy says the coach sees "pass/fail marks,
the priority focus, and the swing reel". W3.4 says his view is "exactly what
the parent sees. No raw footage." The visibility matrix says Swing clips —
Coach: NO. And P-CONSENT promises the parent "a coach you approve sees
pass/fail marks — never your video."
"Swing reel" is overloaded: on P-ROUND it is a grid of CLIPS you tap to
scrub. Drawn here as the STRICTER reading — per-swing marks, no clips —
because that is the only reading consistent with R-03, R-04 and the consent
screen. Derell must rule. The looser reading would require rewriting the
CONSENT copy, not just this screen.""",
    body=f"""
{header('Coach invite')}
<div class="content">
  <div style="display:flex;align-items:center;gap:13px;margin-top:14px">
    <div style="width:46px;height:46px;border-radius:14px;background:{T['field_2']};border:1.5px solid {T['line']};
      display:flex;align-items:center;justify-content:center;font-family:'Oswald',sans-serif;font-weight:700;
      font-size:16px;color:{T['chalk_dim']}">MW</div>
    <div><div style="font-family:'Oswald',sans-serif;font-size:17px;font-weight:600;letter-spacing:.05em;
      text-transform:uppercase">Coach Mike White</div>
      <div class="small">11u Bandits · invited Elijah</div></div>
  </div>
  <div class="eyebrow">What he will see<i></i></div>
  <div class="card"><p class="p" style="font-size:13.5px">The same marks you see — pass or fail on
    each of the six checkpoints, and the one thing to work on — for every round, <b>including ones you
    record at home</b>.</p></div>
  <div class="eyebrow">What he will not see<i></i></div>
  <div style="border:1px solid rgba(217,79,61,.4);background:rgba(217,79,61,.06);border-radius:10px;
    padding:12px 14px">
    <p class="p" style="font-size:13.5px">He cannot see or download <b>any video</b>. He cannot see
    anything you've deleted. He cannot see Mya.</p></div>
  <div style="margin-top:13px;padding:10px 12px;border-radius:9px;background:{T['field_2']};
    border-left:2px solid {T['line']}">
    <div class="small">Home rounds will use his coaching voice. You can switch that back any time,
    privately — he isn't told.</div></div>
  <div class="blocked" style="margin-top:11px"><b>Open — owner Derell</b>
    <p>W1.5's approval copy grants the coach "the swing reel"; the visibility matrix denies him swing
    clips entirely. Drawn as the STRICTER reading — marks only, no clips. Needs a ruling.</p></div>
  <div style="margin-top:13px;padding-bottom:22px;display:flex;flex-direction:column;gap:8px">
    <button class="btn">Approve for Elijah</button>
    <button class="btn ghost">Not now</button>
    <p class="small" style="text-align:center">Turn this off any time in You → Elijah.</p>
  </div>
</div>
""",
))

SCREENS.append(dict(
    slot="P-BILLING", file="Billing.dc.html", page="page-1", title="Subscription",
    release="R3", status="BLOCKED — owner: Derell",
    why="Where the Player tier is sold. Cannot be drawn with a price yet.",
    ruling="""R-26 (2026-09-04) RULED the Player tier at $99/yr or $14.99/mo, one tier,
no free tier — the parent's comparison is a lesson at $60–100, not another app.
BUT the publishable test is `RULED && enforced`, and nothing enforces it: the
StoreKit products do not exist. Under CANON's rule a ruled-but-unenforced
figure MUST NOT appear on any surface a parent could see.
So this screen is drawn in its not-yet state, deliberately, with the price
absent rather than placeholdered. A plausible-looking number here is exactly
the failure R-16 caught in the August mockups.""",
    rejected="""Rendering $99/yr because it is "probably right" — rejected. That is how the
August mockup shipped a price nobody had ruled.
Rendering [YOUR PRICE] — rejected too: a bracketed placeholder in a flow
screen invites someone to fill it in from memory.
A "your coach's seat already covers this athlete, you aren't charged twice"
line — REMOVED 2026-09-13 after review. W1.6 describes it, but no coach tier
is ruled and no seat exists to cover anyone. A fabricated MECHANIC is worse
than a fabricated number: a parent could decline to subscribe on it.""",
    warn="""UNBLOCKS ON: DUG-51 (Paid Apps agreement, tax, banking, Small Business
Program) and the StoreKit products existing. Owner: Derell. Until then this
screen has no number and the flow around it cannot be reviewed for price.""",
    body=f"""
{header('Subscription')}
<div class="content">
  <div class="eyebrow">Player<i></i></div>
  <div style="border:1.5px dashed {T['line']};border-radius:12px;padding:14px 15px;background:{T['card']}">
    <div style="font-family:'Oswald',sans-serif;font-size:17px;font-weight:600;letter-spacing:.06em;
      text-transform:uppercase;color:{T['lights']}">Player</div>
    <div style="margin-top:9px;display:flex;flex-direction:column;gap:5px">
      <div class="small">Up to 2 athletes</div>
      <div class="small">Unlimited rounds on this phone</div>
      <div class="small">Every round graded against the six checkpoints</div>
    </div>
    <div style="margin-top:12px;padding-top:11px;border-top:1px solid {T['line']};
      display:flex;align-items:center;justify-content:space-between">
      <div class="small" style="font-family:'Oswald',sans-serif;letter-spacing:.14em;
        text-transform:uppercase">Price</div>
      <div style="font-family:'Oswald',sans-serif;font-size:14px;letter-spacing:.1em;text-transform:uppercase;
        color:{T['flag']}">Not set</div></div>
  </div>
  <div class="blocked"><b>Blocked · owner Derell</b>
    <p>A price is ruled but nothing charges it yet, so no figure is drawn. Unblocks when the
    Paid Apps agreement (DUG-51) is through and the StoreKit products exist.</p></div>
</div>
{tabbar('you')}
""",
))

SCREENS.append(dict(
    slot="P-DELETE", file="Delete.dc.html", page="page-1", title="Delete account",
    release="R2", status="DRAWN · Apple-mandated",
    why="The exit. App Review rejects the app without it, and COPPA gives it a clock.",
    ruling="""App Review 5.1.1(v) requires in-app account deletion. Deactivation is NOT
sufficient and a link out to a website is NOT sufficient.
W1.7: deleting the account removes the parent record, every profile, every
clip, and every coach link. The flow prompts to cancel the subscription and
deep-links to showManageSubscription() — deleting the account does not cancel
Apple billing, and failing to say so is how you get a chargeback and a
one-star review at once.
§9.4 of the System TDD: deletion is a FOREGROUND operation, not a nightly
batch. The parent watches it happen.""",
    rejected="""A 30-day grace period with soft-delete — rejected: a child's data sitting
recoverable for a month after a parent asked for it gone is the opposite of
the posture, and the retention policy required by §312.10 would have to
disclose it.""",
    body=f"""
{header('Delete account')}
<div class="content">
  <div class="eyebrow" style="color:{T['flag']}">This cannot be undone<i style="background:rgba(217,79,61,.4)"></i></div>
  <div style="display:flex;flex-direction:column;gap:5px">
""" + "".join(
        f"""    <div class="card" style="padding:10px 13px;display:flex;align-items:center;gap:10px">
      <svg viewBox="0 0 24 24" style="width:16px;height:16px;flex:none;fill:none;stroke:{T['flag']};
        stroke-width:2"><path d="M6 6l12 12M18 6L6 18"></path></svg>
      <div style="font-size:13.5px;flex:1">{t}</div></div>
""" for t in ["Your account and sign-in", "Elijah's profile and every clip",
              "Mya's profile and every clip", "Coach Mike's access, immediately",
              "All progress and round history"]
    ) + f"""
  </div>
  <div style="margin-top:14px;padding:12px 14px;border-radius:10px;border:1.5px solid {T['lights']};
    background:{T['field_2']}">
    <div style="font-family:'Oswald',sans-serif;font-size:11.5px;font-weight:600;letter-spacing:.16em;
      text-transform:uppercase;color:{T['lights']};margin-bottom:5px">Cancel your subscription first</div>
    <p class="small">Deleting your account does not stop Apple billing. Tap below to open your
    subscription settings, then come back.</p>
    <div style="margin-top:9px"><button class="btn ghost" style="min-height:42px">Open subscription settings</button></div>
  </div>
  <div style="margin-top:auto;padding-bottom:22px;display:flex;flex-direction:column;gap:8px">
    <button class="btn" style="background:{T['flag']};color:{T['chalk']}">Delete everything</button>
    <button class="btn ghost">Keep my account</button>
  </div>
</div>
""",
))

# ── PAGE 2 · PLAYER (U2) ────────────────────────────────────────────────────

SCREENS.append(dict(
    slot="A-FOCUS", file="PlayerFocus.dc.html", page="page-2",
    title="The one thing", release="R1", status="DRAWN",
    why="Readable from a cage floor, at arm's length, in under fifteen seconds.",
    ruling="""W2.1: the player view is deliberately SMALLER than the parent's. The
priority focus and its drill get a whole screen, at a size that reads when
the phone is on the ground and the kid is standing over it.
W2.3 sets the target: the whole cage loop is prop → hit → look → one thing →
next round, and step four must take under fifteen seconds of reading.""",
    rejected="""Showing the six marks here — rejected: the kid does not need the audit,
he needs the instruction. The marks live one tap away on the parent view.""",
    body=f"""
{header('Elijah')}
<div class="content">
  <div style="flex:1;display:flex;flex-direction:column;justify-content:center;gap:22px">
    <div style="font-family:'Oswald',sans-serif;font-size:12px;font-weight:600;letter-spacing:.24em;
      text-transform:uppercase;color:{T['lights']}">Work on this</div>
    <div style="font-size:27px;line-height:1.28;text-wrap:pretty">Let the barrel find the ball out front.
      Drive it back through the pitcher.</div>
    <div style="padding:13px 15px;border-radius:12px;background:{T['field_2']};border-left:3px solid {T['lights']}">
      <div style="font-family:'Oswald',sans-serif;font-size:11px;font-weight:600;letter-spacing:.18em;
        text-transform:uppercase;color:{T['lights']};margin-bottom:5px">Drill</div>
      <div style="font-size:17px;line-height:1.35">High tee, out front<br>2 rounds of 10</div></div>
  </div>
  <div style="padding-bottom:18px"><button class="btn" style="min-height:54px;font-size:16px">Watch my swings</button></div>
</div>
""",
))

SCREENS.append(dict(
    slot="A-REEL", file="PlayerReel.dc.html", page="page-2", title="My swings",
    release="R1", status="DRAWN",
    why="The kid's own footage. The part he actually wants.",
    ruling="""Scrub, slow-mo, and the shadow-swing compare (W2.1). Same clips as the
parent's film space — the player view is a narrower window onto the same
data, never a separate store.""",
    rejected="""Sharing to social from here — rejected: the clip is a minor's video under
R-04, and an export affordance on a child-facing screen is indefensible
regardless of what the parent consented to.""",
    body=f"""
{header('My swings')}
<div style="flex:none;height:330px;background:linear-gradient(165deg,#16301f,{T['field']});
  border-bottom:1px solid {T['line']};position:relative;display:flex;align-items:center;justify-content:center">
  <div style="font-family:'Oswald',sans-serif;font-size:11px;letter-spacing:.2em;text-transform:uppercase;
    color:rgba(245,242,232,.3)">Swing 5</div>
  <div style="position:absolute;left:14px;right:14px;bottom:14px;height:5px;border-radius:3px;
    background:rgba(245,242,232,.16)"><div style="width:62%;height:100%;border-radius:3px;
    background:{T['lights']}"></div></div>
</div>
<div class="content">
  <div style="display:flex;gap:8px;margin-top:14px">
    <div style="flex:1;text-align:center;padding:12px;border-radius:10px;background:{T['lights']};color:#1a1205;
      font-family:'Oswald',sans-serif;font-size:13px;letter-spacing:.1em;text-transform:uppercase">Slow</div>
    <div style="flex:1;text-align:center;padding:12px;border-radius:10px;border:1px solid {T['line']};
      font-family:'Oswald',sans-serif;font-size:13px;letter-spacing:.1em;text-transform:uppercase;
      color:{T['chalk_dim']}">Compare</div>
  </div>
  <div class="eyebrow">This round<i></i></div>
  <div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:7px">
""" + "".join(
        f"""    <div style="height:80px;border-radius:8px;background:{T['field_2']};
      border:{'1.5px solid ' + T['lights'] if i == 5 else '1px solid ' + T['line']};position:relative">
      <div style="position:absolute;right:6px;top:5px;font-family:'Oswald',sans-serif;font-size:11px;
        color:{T['chalk_dim']}">{i}</div></div>
""" for i in range(1, 9)
    ) + """
  </div>
</div>
""",
))

SCREENS.append(dict(
    slot="A-STREAKS", file="PlayerStreaks.dc.html", page="page-2", title="Streaks",
    release="R1", status="DRAWN",
    why="The only scoreboard the product allows, and it is a scoreboard against himself.",
    ruling="""W2.1: streaks — "Contact: 4 straight". A streak is a count of consecutive
passes, which is a fact about this athlete's own rounds. It is NOT a score
and NOT a comparison, so it survives R-02.
W1.4 bars the alternatives explicitly: never a number, never a grade, never
a percentile against other kids.""",
    rejected="""A leaderboard, a team ranking, or a percentile — rejected under W1.4 and
the whole positioning. The moment a kid can see he is 9th of 12, the product
becomes the thing parents are trying to get away from.""",
    body=f"""
{header('Streaks')}
<div class="content">
  <div class="eyebrow">Going right now<i></i></div>
  <div style="display:flex;flex-direction:column;gap:7px">
""" + "".join(
        f"""    <div style="display:grid;grid-template-columns:1fr auto;align-items:center;gap:12px;
      background:{T['card']};border:1px solid {T['line']};border-left:3px solid {T['pass'] if n >= 4 else T['line']};
      border-radius:10px;padding:12px 14px">
      <div style="font-family:'Oswald',sans-serif;font-size:16px;font-weight:600;letter-spacing:.06em;
        text-transform:uppercase">{name}</div>
      <div style="font-family:'Oswald',sans-serif;font-size:22px;font-weight:700;line-height:1;
        color:{T['pass'] if n >= 4 else T['chalk_dim']};font-variant-numeric:tabular-nums">{n}</div>
    </div>
""" for name, n in [("Stance", 6), ("Finish", 6), ("Hips fire", 6), ("Load", 5), ("Stride", 2)]
    ) + f"""
  </div>
  <div style="margin-top:14px;padding:12px 14px;border-radius:10px;background:{T['field_2']};
    border-left:2px solid {T['lights']}">
    <div style="font-size:14px;line-height:1.45">Contact is the one to break. No streak
      going on it yet.</div></div>
  <div class="small" style="margin-top:auto;padding-bottom:20px;text-align:center">
    Straight passes in a row. Only against your own rounds — never against anyone else.</div>
</div>
""",
))

SCREENS.append(dict(
    slot="A-EXCLUDED", file="PlayerExcluded.dc.html", page="page-2",
    title="What the player cannot reach", release="R1", status="DRAWN · permission artboard",
    why="The absence IS the ruling. Drawn so it can be reviewed, because it is otherwise invisible.",
    ruling="""W2.1 lists what the player view does NOT show: billing, coach linking,
consent, deletion, other profiles. That list is a permission decision, and a
permission decision nobody can see is a permission decision nobody reviews.
The visibility matrix is the authority: a player sees his own clips, his own
marks, his own trends and streaks — and no billing, no consent record, and
nothing belonging to a sibling.""",
    rejected="""Leaving this undrawn and trusting the workflows doc — rejected: every other
screen on this canvas can be checked by looking at it, and this one could not.
An absent screen invites the question later; a screen that says "not here,
and here's why" answers it now.""",
    body=f"""
{header('Player view')}
<div class="content">
  <div class="eyebrow">Reachable<i></i></div>
  <div style="display:flex;flex-direction:column;gap:5px">
""" + "".join(
        f"""    <div style="display:flex;align-items:center;gap:10px;background:{T['card']};border:1px solid {T['line']};
      border-radius:9px;padding:10px 13px">
      <svg viewBox="0 0 24 24" style="width:16px;height:16px;flex:none;fill:none;stroke:{T['pass']};stroke-width:2.2">
        <path d="M4 12.5l5 5L20 6.5"></path></svg>
      <div style="font-size:13.5px;flex:1">{t}</div></div>
""" for t in ["The priority focus and its drill", "His own swing clips",
              "His own streaks and trends"]
    ) + f"""
  </div>
  <div class="eyebrow" style="color:{T['flag']}">Not reachable<i style="background:rgba(217,79,61,.4)"></i></div>
  <div style="display:flex;flex-direction:column;gap:5px">
""" + "".join(
        f"""    <div style="display:flex;align-items:center;gap:10px;border:1px solid rgba(217,79,61,.35);
      background:rgba(217,79,61,.05);border-radius:9px;padding:10px 13px">
      <svg viewBox="0 0 24 24" style="width:16px;height:16px;flex:none;fill:none;stroke:{T['flag']};stroke-width:2.2">
        <path d="M6 6l12 12M18 6L6 18"></path></svg>
      <div style="font-size:13.5px;flex:1">{t}</div></div>
""" for t in ["Billing and subscription", "Linking or removing a coach",
              "The consent record", "Deleting anything", "A sibling's profile"]
    ) + f"""
  </div>
  <div class="blocked" style="border-style:solid;border-color:{T['line']};background:{T['field_2']}">
    <b style="color:{T['lights']}">Why this artboard exists</b>
    <p>The absence is the ruling. Drawn so it can be reviewed — every other screen here
    can be checked by looking at it, and this one could not.</p></div>
</div>
""",
))

# ── PAGE 3 · STATES & FAILURES (S) ──────────────────────────────────────────
# Nobody draws these and every one is a real path in W1.2. A failure screen
# that was never designed gets improvised at 11pm by whoever hits the bug.

def _state(slot, file, title, release, status, why, ruling, rejected,
           headline, body_copy, actions, tone="flag", warn=None, foot=None):
    accent = T[tone]
    acts = "".join(
        f"""    <button class="btn{' ghost' if i else ''}">{a}</button>\n"""
        for i, a in enumerate(actions))
    footer = f"""<div style="margin-top:13px;padding:10px 12px;border-radius:9px;background:{T['field_2']};
    border-left:2px solid {T['line']}"><div class="small">{foot}</div></div>""" if foot else ""
    return dict(
        slot=slot, file=file, page="page-3", title=title, release=release,
        status=status, why=why, ruling=ruling, rejected=rejected, warn=warn,
        body=f"""
{header(title)}
<div class="content">
  <div style="flex:1;display:flex;flex-direction:column;justify-content:center;gap:15px">
    <div style="width:42px;height:3px;border-radius:2px;background:{accent}"></div>
    <div style="font-family:'Oswald',sans-serif;font-size:23px;font-weight:600;letter-spacing:.04em;
      text-transform:uppercase;line-height:1.24">{headline}</div>
    <p class="p">{body_copy}</p>
    {footer}
  </div>
  <div style="padding-bottom:22px;display:flex;flex-direction:column;gap:8px">
{acts}  </div>
</div>
""")


SCREENS.append(_state(
    "S-NO-SWINGS", "StateNoSwings.dc.html", "No swings found", "R1", "DRAWN",
    why="The most likely failure in the product, and the one that decides whether they try again.",
    ruling="""W1.2 failure table: show framing tips AND **keep the clip**. Do not delete
their footage on a failure — a parent who loses a round of their kid's cage
work to a bug does not record a second one.
The tone is ours-not-yours: the app failed to find swings, the kid did not
fail to swing.""",
    rejected="""Deleting the footage to honour R-04's delete-at-segmentation rule —
rejected: segmentation did not complete, so the rule has not fired. The clip
is held for retry and deleted when the retry segments or the user discards it.""",
    warn="""This is the screen SPIKE_ENTER_MULT was producing on BOTH ground-truth clips
until 3b7fae6. CANON R-14: the diagnosis is resolved, the value 2.4 is still
provisional on proxy-codec measurement. Treat any field report of this screen
as a threshold question first, a framing question second.""",
    headline="We couldn't find<br>swings in this one",
    body_copy="Your footage is saved — nothing was lost. Most of the time it's the framing.",
    foot="Side view · full body in frame · bat visible at the top of the load · phone still",
    actions=["Try this clip again", "Record a new round", "Keep it and decide later"]))

SCREENS.append(_state(
    "S-PARTIAL", "StatePartial.dc.html", "Round interrupted", "R1", "DRAWN",
    why="A phone call, a lock, a kid walking off. The round is half-captured and still useful.",
    ruling="""W1.2: save what was captured and OFFER to analyze the partial round.
Never discard silently. Forty seconds of a ninety-second round is six or
seven swings — enough for a pattern, which is all ER-03 requires.""",
    rejected="""Auto-analyzing the partial without asking — rejected: a round the parent
did not intend to end shouldn't silently become a graded round in the
history and pull the trend around.""",
    tone="lights",
    headline="That round stopped<br>at 41 seconds",
    body_copy="We kept what was recorded — about seven swings. Enough to look at, if you want.",
    foot="A pattern needs more than one swing. Seven is plenty.",
    actions=["Analyze what we got", "Discard it", "Record again"]))

SCREENS.append(_state(
    "S-OFFLINE", "StateOffline.dc.html", "No signal", "R1", "DRAWN",
    why="The cage has no signal. This is a feature screen, not an error screen.",
    ruling="""CLAUDE.md invariant #2 and W1.2: everything above still works offline. The
AI degrades to the deterministic stub; capture, segmentation, evaluation and
the round card all run on device.
"This is a feature — the cage has no signal." The screen must READ as
reassurance, which is why it uses the lights accent and not the flag.""",
    rejected="""A blocking error or a queue-for-later state — rejected: there is nothing
to queue. The pipeline is local by design (R-25), and presenting offline as
degraded would misrepresent the architecture to the user.""",
    tone="lights",
    headline="You're offline —<br>keep hitting",
    body_copy="Everything works without signal. Rounds record, swings get found, and you get your one thing to fix. Nothing is waiting to upload.",
    foot="Batting cages are famously bad for signal. This was designed for that.",
    actions=["Start a round"]))

SCREENS.append(_state(
    "S-CADENCE", "StateCadence.dc.html", "Enough for today", "R1", "DRAWN",
    why="A soft guard against a parent recording eleven rounds in an afternoon.",
    ruling="""W1.2: the cadence guard is 2–3 sessions per day per profile and it is a
SOFT message, not a hard wall. The parent can proceed.
Two reasons it exists and only one is about cost: repeated same-day rounds
produce correlated results that pull trends without adding information, and
an 11-year-old taking a fourth filmed round in one day is a youth-sports
problem the product should not accelerate.""",
    rejected="""A hard block — rejected: a tournament day or a lesson plus a cage session
is legitimate, and a wall here would be the app overriding a parent about
their own kid.""",
    tone="lights",
    headline="Third round today",
    body_copy="You can keep going. Worth knowing: rounds close together tend to look the same, so the trend won't move much until tomorrow.",
    foot="No limit here — just a nudge.",
    actions=["Record anyway", "Stop for today"]))

SCREENS.append(_state(
    "S-TRIM", "StateTrim.dc.html", "Clip is long", "R1", "DRAWN",
    why="Uploaded footage longer than the cap. Show the trim; never trim silently.",
    ruling="""W1.2 Path B: longer than the cap shows "We'll analyze the first 90 seconds"
with the trim SHOWN, not silent. A silent trim is how a parent concludes the
app missed the swings that mattered.""",
    rejected="""Analyzing the whole clip however long — rejected: an unbounded clip breaks
the per-session background model and the ~6s cadence prior that R-25's
reconcile stage depends on.""",
    tone="lights",
    headline="That clip is<br>four minutes long",
    body_copy="We'll look at the first ninety seconds — about fifteen swings. You can pick a different starting point first.",
    foot="Your original file isn't changed.",
    actions=["Analyze the first 90 seconds", "Choose where to start", "Cancel"]))

SCREENS.append(_state(
    "S-FREE-LIMIT", "StateFreeLimit.dc.html", "Free round used", "R3",
    "BLOCKED — owner: Derell",
    why="The metering moment. Blocked because the tier it meters against is unruled.",
    ruling="""W1.6: metering must be visible BEFORE the session starts, not after — a
parent who films a round and then learns it won't be analyzed has been
cheated of the round, not just the analysis.
R-26 ruled ONE tier and NO free tier. The workflows doc (2026-08-30, never
locked) describes a free tier of 1 session/month. These disagree, and R-26 is
newer and is a ruling — so this screen may not exist at all.""",
    rejected="""Drawing it with a price — rejected under the same rule as P-BILLING: R-26
is ruled and NOT publishable until StoreKit charges it.""",
    warn="""TWO open questions, not one. (1) Does a free tier exist? R-26 says no; the
unlocked workflows doc says 1 session/month. (2) If it does, what does it
cost to leave? Both are Derell's. The screen is drawn in its not-yet state so
the flow has a shape to review, not to propose a free tier.""",
    tone="flag",
    headline="This is where<br>metering would go",
    body_copy="R-26 ruled one paid tier and no free tier. The user-workflows draft — written before that ruling and never locked — describes one free session a month. Until that's settled this screen may not exist.",
    foot="Whatever is ruled, the limit is shown BEFORE a round is filmed, never after.",
    actions=["— blocked —"]))


# ═══════════════════════════════════════════════════════════════════════════
# BUILD — emit one .dc.html per screen, plus canvas.json
# ═══════════════════════════════════════════════════════════════════════════

PAGES = [
    {"id": "page-1", "name": "Parent"},
    {"id": "page-2", "name": "Player"},
    {"id": "page-3", "name": "States & failures"},
]

PER_ROW = 5
STEP_X = PHONE_W + 90      # >=80px between frames in a row
STEP_Y = PHONE_H + 150     # >=120px between rows (name strip + chips sit above)

PAGE_NOTES = {
    "page-1": ("PARENT — U1, the profile owner. 19 screens, left to right in flow order: "
               "onboard once, record a round, read one thing, watch it move over weeks, then the "
               "exits Apple requires.\n\nThe athlete profile is PARENT-OWNED. A coach never creates "
               "or owns child data; he is granted a results-only view and the parent revokes it "
               "without asking anyone.\n\nEvery artboard carries its ruling in the source comment at "
               "the top of the file — what it is for, what was rejected, and where the code "
               "contradicts the drawing today."),
    "page-2": ("PLAYER — U2. Deliberately smaller than the parent view: the one thing, his swings, "
               "his streaks.\n\nThe fourth artboard draws what he CANNOT reach. The absence is a "
               "permission ruling, and a ruling nobody can see is a ruling nobody reviews."),
    "page-3": ("STATES & FAILURES — every one of these is a real path in W1.2, and a failure screen "
               "that was never designed gets improvised at 11pm by whoever hits the bug.\n\n"
               "S-OFFLINE is a FEATURE screen, not an error: the cage has no signal and the whole "
               "pipeline is local by design."),
}


def build():
    seen = {}
    for s in SCREENS:
        stem = s["file"].split(".")[0].lower()
        if stem in seen:
            raise SystemExit(f"duplicate artboard stem: {s['file']} and {seen[stem]}")
        seen[stem] = s["file"]
        with open(os.path.join(OUT, s["file"]), "w", encoding="utf-8") as fh:
            fh.write(emit(s))

    artboards, annotations = [], []
    for page in PAGES:
        pid = page["id"]
        rows = [s for s in SCREENS if s["page"] == pid]
        for i, s in enumerate(rows):
            artboards.append({
                "file": s["file"],
                "x": (i % PER_ROW) * STEP_X,
                "y": (i // PER_ROW) * STEP_Y,
                "w": PHONE_W, "h": PHONE_H,
                "title": f"{s['slot']} · {s['title']}",
                "page": pid,
            })
        annotations.append({
            "id": f"intro-{pid}", "page": pid,
            "x": 0, "y": -300, "w": 900, "text": PAGE_NOTES[pid],
        })

    blocked = [s for s in SCREENS if s["status"].startswith("BLOCKED")]
    annotations.append({
        "id": "blocked-index", "page": "page-1",
        "x": PER_ROW * STEP_X, "y": -300, "w": 460,
        "text": "BLOCKED, AND ON WHOM\n\n" + "\n".join(
            f"· {s['slot']} — {s['status'].split('—')[-1].strip()}" for s in blocked
        ) + "\n\nThese are drawn in their not-yet state and say on the face of the artboard "
             "what is missing. None renders a number the product cannot honestly compute.",
    })

    canvas = {
        "artboards": artboards,
        "annotations": annotations,
        "pages": PAGES,
        "launch": {"view": "canvas", "page": "page-1"},
    }
    with open(os.path.join(OUT, "canvas.json"), "w", encoding="utf-8") as fh:
        json.dump(canvas, fh, indent=2)

    drawn = sum(1 for s in SCREENS if not s["status"].startswith("BLOCKED"))
    warned = sum(1 for s in SCREENS if s.get("warn"))
    print(f"{len(SCREENS)} artboards · {drawn} drawn · {len(blocked)} blocked · "
          f"{warned} carry a code-contradiction warning")
    return [s["file"] for s in SCREENS]


if __name__ == "__main__":
    for f in build():
        print("  ", f)
