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
2. Select the **DugOut** target → **Signing & Capabilities**. The Team must be
   **Restorative Labs LLC (`NKNR8F3VKC`)** — the paid Organization account. It is
   set in the project already; if Xcode shows a personal team instead, you are
   signed into the wrong Apple ID.
3. Plug in your iPhone (Developer Mode already on), pick it as the run
   destination, press **Run**.
4. First install on a phone: Settings → General → VPN & Device Management →
   trust the developer certificate.
5. First camera use shows the one-time iOS Camera/Microphone permission
   prompts — accept both.

## Demo notes

- Fully offline once installed — the Oswald/Inter woff2 faces are self-hosted in
  `css/fonts/`, so there is no network reference of any kind. AI analysis calls
  `api.anthropic.com` and degrades to the deterministic stub offline, as designed;
  with no key entered (You → App) the AI features stay hidden rather than broken.
- Signing lasts a year on the Organization account, so the old 7-day re-Run dance
  before a demo is gone. (It applied to the free personal team the project used
  until Sep 8 2026.)
- Data (profiles, rounds, clips) lives in the app's own WKWebView storage —
  separate from Safari's, and it survives rebuilds/reinstalls of the same app.

## TestFlight — one command (DUG-63)

```
cd ios && fastlane beta
```

That checks the files, picks the next build number, archives, checks the built app,
uploads it to App Store Connect, waits for processing and confirms the build is in the
**DugOut testers** group (automatic distribution is on, so testers get it with no hand
step). `fastlane beta dry_run:true` does everything except the upload.

- **Ships exactly a commit.** The lane refuses a working tree with uncommitted changes.
- **Build number** = one above the highest of TestFlight's latest upload and the project's
  `CURRENT_PROJECT_VERSION`, passed to the archive. The project file is not rewritten.
- **No Apple ID sign-in.** It authenticates with the App Store Connect API key
  (`~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`, team key "DugOut fastlane"). Key ID
  and Issuer ID come from the environment, an untracked `ios/fastlane/.env`, or
  `~/.appstoreconnect/dugout.env`. Never commit any of them.
- **Signing**: the Restorative Labs LLC Apple Distribution certificate in the login keychain;
  Xcode creates or refreshes the App Store profile with the API key.
- **The build stops** if `scripts/ship_checks.py` finds an outside address in the app's entry
  point (DUG-96), SharePoint marks in a shipped file (DUG-97), or a web file in the built app
  that differs from the repo (DUG-44 — the web app ships inside the app, untouched; no
  over-the-air updates). It runs on the source before the archive and on the `.ipa` after.
  `python3 scripts/test_ship_checks.py` plants each violation and proves it fails.
- Needs fastlane (Homebrew) and Xcode. Build output goes to `ios/fastlane/build/` (ignored).

## Updating the web app

Nothing to do — edit `index.html` / `js/` / `css/` as usual and press Run.
Only if you add a **new top-level file or folder** to the repo root does it
need to be added to the Xcode project (right-click the "Web App" group →
Add Files, and untick "Copy items if needed").

## Debugging

Run a Debug build, then on your Mac: Safari → Develop → your iPhone →
DugOut — full Web Inspector against the running app.
