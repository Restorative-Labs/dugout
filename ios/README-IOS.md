# DugOut — iOS wrapper (WKWebView)

A dependency-free Xcode project that runs the DugOut web app (`../index.html`)
as a native iPhone app. No Node, no CocoaPods, no build steps — open, sign, Run.

## How it works

- The project references the web app files **in place** (`index.html`, `css/`,
  `js/`, `vendor/`, `shadow-sprite.jpg`, `swing-shadow.mp4` from the repo root).
  Every build bundles whatever is currently on disk, so edits to the web app
  are picked up on the next Run automatically.
- At launch the app starts a tiny loopback HTTP server (`LocalHTTPServer.swift`)
  and points a full-screen WKWebView at `http://127.0.0.1:8384/index.html`.
  Serving over localhost (instead of `file://`) is what makes in-app camera
  recording (`getUserMedia`), the local MoveNet pose model (`fetch`), video
  scrubbing (byte ranges), and IndexedDB/localStorage persistence all work.
- The screen stays awake while the app is open (film-room sessions).

## First run

1. Open `ios/DugOut.xcodeproj` in Xcode.
2. Select the **DugOut** target → **Signing & Capabilities** → pick your Team.
   (If the bundle id collides with something, change `com.restorativelabs.dugout`
   to anything unique.)
3. Plug in your iPhone (Developer Mode already on), pick it as the run
   destination, press **Run**.
4. Free Apple ID only: on the phone, Settings → General → VPN & Device
   Management → trust your developer certificate the first time.
5. First camera use shows the one-time iOS Camera/Microphone permission
   prompts — accept both.

## Demo notes

- Fully offline once installed (Google Fonts fall back to system fonts with no
  Wi-Fi; everything else is bundled). AI analysis calls `api.anthropic.com`
  and degrades to the deterministic stub offline, as designed.
- **Free Apple ID signing expires after 7 days** — re-Run from Xcode the day
  before a demo. A paid developer account ($99/yr) extends this to a year and
  unlocks TestFlight.
- Data (profiles, rounds, clips) lives in the app's own WKWebView storage —
  separate from Safari's, and it survives rebuilds/reinstalls of the same app.

## Updating the web app

Nothing to do — edit `index.html` / `js/` / `css/` as usual and press Run.
Only if you add a **new top-level file or folder** to the repo root does it
need to be added to the Xcode project (right-click the "Web App" group →
Add Files, and untick "Copy items if needed").

## Debugging

Run a Debug build, then on your Mac: Safari → Develop → your iPhone →
DugOut — full Web Inspector against the running app.
