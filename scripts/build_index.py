import io
import os

ROOT = "/Users/derelljenkins/Library/CloudStorage/OneDrive-Personal/Restorative Labs LLC/04 — Dugout/dugout"
SCRATCH = "/private/tmp/claude-501/-Users-derelljenkins-Library-CloudStorage-OneDrive-Personal-Restorative-Labs-LLC-04---Dugout/7368adf0-28b5-43b5-a85e-d8e9b0b656ea/scratchpad"

main_inner = io.open(os.path.join(SCRATCH, "main_inner.html"), encoding="utf-8").read()

# The film room keeps its own numbered sections; it is now one view among several.
film_view = main_inner

HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Dugout · Hitting — Film Room</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Oswald:wght@500;600;700&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="css/app.css">
<link rel="stylesheet" href="css/session.css">
</head>
<body>

<header>
  <div class="brand">
    <h1>Dug<span>out</span></h1>
    <span class="inning">Hitting · Film Room</span>
    <span class="spacer"></span>
    <span class="chip" id="profileChip" hidden></span>
  </div>
  <nav class="topnav">
    <a href="#/home" id="navHome" class="on">Rounds</a>
    <a href="#/film" id="navFilm">Film room</a>
    <a href="#/progress" id="navProgress">Progress</a>
    <a href="#/philosophy" id="navPhilosophy">My philosophy</a>
  </nav>
</header>

<!-- ============ HOME / ROUNDS ============ -->
<main id="view-home">
  <div class="eyebrow">Who's hitting?</div>
  <div id="profileList" class="plist"></div>

  <p class="hint" id="noProfile">Add a hitter to get started. Every round attaches to a profile so his progress builds up over time.</p>
  <button class="btn btn-ghost" id="addProfile">+ Add a hitter</button>

  <div class="sheet" id="profileForm" hidden>
    <label class="fl">Name<input id="pfName" maxlength="24" placeholder="e.g. Miles"></label>
    <label class="fl">Age<select id="pfBand">
      <option value="7-10">7–10</option>
      <option value="11-13" selected>11–13</option>
      <option value="14-18">14–18</option>
    </select></label>
    <p class="err" id="pfErr"></p>
    <div class="srow">
      <button class="btn btn-amber" id="pfSave">Save</button>
      <button class="btn btn-ghost" id="pfCancel">Cancel</button>
    </div>
  </div>

  <div id="roundActions">
    <div class="eyebrow">Run a round</div>
    <div class="bigbtns">
      <button class="bigbtn" id="btnRound">
        <span class="bb-ic">&#9654;</span>
        <span class="bb-t">Analyze a Round</span>
        <span class="bb-s">Upload a cage or BP video — we find each swing</span>
      </button>
      <button class="bigbtn" id="btnRecord">
        <span class="bb-ic">&#9679;</span>
        <span class="bb-t">Record a Round</span>
        <span class="bb-s">Film right here, stops itself at 90 seconds</span>
      </button>
      <button class="bigbtn ghost" id="btnSingle">
        <span class="bb-ic">&#9633;</span>
        <span class="bb-t">Just one swing</span>
        <span class="bb-s">Single clip — same read, round of one</span>
      </button>
    </div>
    <p class="hint">Best angle: side view, waist height, whole body in frame. Slo-mo if your phone has it.</p>
  </div>

  <div id="recentWrap" hidden>
    <div class="eyebrow">Recent rounds</div>
    <div id="recentRounds" class="rlist"></div>
  </div>

  <div class="sheet" id="recSheet" hidden>
    <h3>How long?</h3>
    <div class="srow">
      <button class="rec-preset" data-secs="60">60s</button>
      <button class="rec-preset on" data-secs="90">90s</button>
    </div>
    <p class="hint">It stops on its own at time, or after 15 swings — whichever comes first. Recording uses the battery hard; plug in for long sessions.</p>
    <div class="srow">
      <button class="btn btn-amber" id="recStart">Start recording</button>
      <button class="btn btn-ghost" id="recCancel">Cancel</button>
    </div>
  </div>

  <input type="file" id="fileRound" accept="video/*">
  <input type="file" id="fileSingle" accept="video/*">
</main>

<!-- ============ CAPTURE / PROGRESS ============ -->
<main id="view-capture" hidden>
  <div class="eyebrow" id="capTitle">Reading the round</div>

  <div id="recLive" hidden>
    <div class="stage recstage">
      <video id="recPreview" playsinline muted></video>
      <div class="countwrap"><span id="recCount">90</span></div>
      <div class="reclabel"><span class="dot"></span> REC · <span id="recSwings">0</span> swings</div>
    </div>
    <button class="btn btn-ghost" id="recStopNow" style="margin-top:10px">Stop now</button>
  </div>

  <div class="progwrap">
    <div class="progbar"><i id="capBar"></i></div>
    <p class="ai-status" id="capStatus"></p>
    <p class="err" id="capErr" hidden></p>
    <p class="hint" id="capDone" hidden></p>
  </div>
  <button class="btn btn-ghost" id="capBack">Back</button>
</main>

<!-- ============ ROUND CARD ============ -->
<main id="view-round" hidden>
  <div class="rc-head">
    <div>
      <div class="rc-date" id="rcDate"></div>
      <div class="rc-who" id="rcWho"></div>
    </div>
  </div>
  <p class="capnote" id="rcCap" hidden></p>

  <div class="celebrate" id="rcCelebrate" hidden>All six ✓ — that's a clean round.</div>

  <!-- verbal first: the correction leads, drills come after -->
  <div class="rc-focus">
    <h2 id="rcHeadline"></h2>
    <p id="rcBody"></p>
    <div class="cueline" id="rcCueWrap">
      <b>Say this to him</b>
      <div id="rcCue"></div>
      <button class="mini" id="rcCorrect">That's not how I'd say it</button>
    </div>
    <div id="rcDrillWrap">
      <h4>Drills to try</h4>
      <ul id="rcDrills"></ul>
    </div>
    <p class="src" id="rcSource"></p>
  </div>

  <div class="eyebrow">The six checkpoints</div>
  <div class="marks" id="rcMarks"></div>

  <div class="eyebrow">Every swing</div>
  <div class="reel" id="rcReel"></div>

  <div class="sheet" id="slangSheet" hidden>
    <h3>Say it your way</h3>
    <p class="hint">Same fix, your words. This only changes how it's worded — never which tip he gets.</p>
    <div class="sl-cur" id="slangCurrent"></div>
    <input id="slangInput" placeholder="What do YOU say for this?">
    <p class="err" id="slangErr" hidden></p>
    <div class="srow">
      <button class="btn btn-amber" id="slangSave">Save my words</button>
      <button class="btn btn-ghost" id="slangCancel">Cancel</button>
    </div>
  </div>
</main>

<!-- ============ PROGRESS ============ -->
<main id="view-progress" hidden>
  <div class="eyebrow">Progress · <span id="pgWho"></span></div>
  <p class="hint" id="pgEmpty">Run two rounds and his checkpoint streaks show up here.</p>
  <div id="pgBody" hidden>
    <div id="pgList" class="pglist"></div>
    <p class="hint">Each row is one checkpoint, oldest round on the left. Streaks are what matter — one rough round is just a rough round.</p>
  </div>
</main>

<!-- ============ PHILOSOPHY ============ -->
<main id="view-philosophy" hidden>
  <div class="eyebrow">My philosophy</div>
  <p class="hint">Pick how you teach. Dugout words every correction this way — same fix, your voice. Takes about five minutes, mostly tapping.</p>

  <div class="eyebrow">1 · Start from a school</div>
  <div class="presets" id="phPresets"></div>

  <div class="eyebrow">2 · Which tips do you use?</div>
  <div id="phTips"></div>

  <div class="eyebrow">3 · What matters most?</div>
  <div id="phOrder"></div>

  <div class="eyebrow">4 · Your words</div>
  <div id="phSlang"></div>

  <div class="eyebrow">Never said</div>
  <ul class="dep" id="phDeprecated"></ul>
  <p class="hint">These stay out of every correction Dugout writes.</p>

  <div class="srow" style="margin-top:16px">
    <button class="btn btn-amber" id="phSave">Save philosophy</button>
    <button class="btn btn-ghost" id="phReset">Reset to suggested</button>
    <span class="saved" id="phSaved">Saved ✓</span>
  </div>
</main>

<!-- ============ FILM ROOM (v1) ============ -->
<main id="view-film" hidden>
__FILM__
</main>

<footer>ONE ROUND · SIX CHECKPOINTS · ONE THING TO FIX</footer>

<script src="vendor/tf-core.min.js"></script>
<script src="vendor/tf-converter.min.js"></script>
<script src="vendor/tf-backend-webgl.min.js"></script>
<script src="vendor/pose-detection.min.js"></script>
<script src="js/config.js"></script>
<script src="js/library.js"></script>
<script src="js/store.js"></script>
<script src="js/pose.js"></script>
<script src="js/segment.js"></script>
<script src="js/evaluate.js"></script>
<script src="js/ai.js"></script>
<script src="js/filmroom.js"></script>
<script src="js/app.js"></script>
</body>
</html>
"""

out = HTML.replace("__FILM__", film_view)
io.open(os.path.join(ROOT, "index.html"), "w", encoding="utf-8").write(out)
print("index.html %d bytes" % os.path.getsize(os.path.join(ROOT, "index.html")))
