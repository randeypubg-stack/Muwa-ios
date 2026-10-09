# Muwa build 49: layout and recognition contracts

## Navigation and player

The root content already respects the scene safe area. Bottom navigation keeps a
9-point content margin on iPhone and no extra margin on iPad. Its 62-point height
and the 8-point mini-player gap share `BottomChromeLayout`; never add the system
bottom inset a second time. Player geometry uses the same anchor. Short landscape
layouts preserve the title clearance and full transport/action touch targets.

`NativeInteractionTests` checks the actual bar across Home, Library, Profile and
Player, plus real device rotation, queue dragging, playlist persistence, artwork
fill, buffering/pause and subtitle reader presentation. Long Arabic phrases wrap
and can scroll inside the rail; their drag must not page artwork or collapse the
player. Original text and audio time remain unchanged. Preparation checks compare
the four reviewed source files byte-for-byte and reject duplicate implementations.

The owner reported iPhone 17 Pro / iOS 27.2. The explicit `reported-phone` profile
requires the real model. CI reports the actual installed runtime and marks 27.2
unavailable when only stable 27.0 is installed. Never relabel a simulator capture.
A physical device check remains necessary for an unavailable OS combination.

## Recognition and administration

Verified catalog uploads from the panel, Telegram bot, and approved submissions
queue local recognition in the same database transaction. Recognize the original
language; Arabic dialect tags map to Arabic transcription. The worker runs one
recording at a time on the beta VPS. Supported jobs are MP3/M4A/WAV, at most one
hour, with a verified stored audio fingerprint. Upload/publication are independent
of recognition. Manual captions and results for a different recording are protected.

The panel reports current jobs across the active catalog, without retrieving whole
transcripts for the dashboard. Ready results that need review have a separate
count and visible warning. Recognition results remain private to administrators.
The owner can open subtitles, import the recognized original, review and save.

A generic or malformed title can receive a suggestion quoted from an opening or
repeated recognized phrase. This is not identification of the official title.
Applying the suggestion changes only the editor field. Saving still requires the
existing explicit action and revision check; metadata is never renamed by ASR.

## Repeatable checks

- Backend: `npm test`, `npm run typecheck`, `npm run build`, `npm run test:runtime`
  in `backend`; database tests accept only a local disposable `muwa_audit` DB.
- Panel: `npm run build` in `admin-panel`. Launch its local preview on port 4173,
  then run `python tests/AdminWorkspaceChecks.py --output build/panel-review`.
  The browser check requires Python Playwright and its Chromium installation.
  It renders real components with isolated API fixtures; it does not test live
  authorization. Native and backend checks cover that separately.
- Native: the release workflow compiles the canonical Swift files, runs foundation
  checks, then native interaction tests on iPhone and iPad. Review screenshots and
  actual runtime evidence before calling a changed release verified.

Keep commits, artifact hashes, source equivalence and observed CI results with the
release. These checks detect regressions; they do not make code immutable or
replace repository branch protections. No branch protection was changed here.
