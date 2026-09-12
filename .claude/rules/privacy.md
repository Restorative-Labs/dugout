---
paths:
  - "js/{store,ai}.js"
  - "ios/**"
  - "scripts/**"
---
# Minors' data and secrets — how to work here

DugOut's users are children. The 2025 COPPA amendments' compliance date (2026-04-22) has
passed, and **"gait patterns" is now an enumerated biometric identifier** — which is what pose
keypoints are.

## Never, in any environment, at any log level

Clip bytes or frames · pose keypoints · a child's name · internal checkpoint scores · auth
tokens · Apple identity tokens. Logs reference the opaque `profileId` only (R-13).

## Never committed

Video and raw footage · the tip-library spreadsheet · API keys, tokens, `.env` files, `.p8`
files, signing certs · `node_modules/` · `__pycache__/` · `.DS_Store`.
**A committed key is a compromised key — rotate it, do not merely delete it.**

## Hard rules

1. **The app never ships an API key** (R-09). The key lives only in a server-side proxy.
2. **Tokens live in the iOS Keychain** via the bridge, never `localStorage` (R-10).
3. **No third-party SDKs in the app** (R-11). A vendor's SDK behaviour becomes your violation.
4. **Staging carries synthetic athlete data only** (R-12). Never a real child's session, in any
   environment, for any reason. Production credentials never touch a laptop.
5. Every stored object carries `profileId` so accounts can bolt on later.

## When this rule and a deadline disagree

The rule wins, and you say so rather than shipping and noting it. There is no version of this
product that survives a COPPA finding.
