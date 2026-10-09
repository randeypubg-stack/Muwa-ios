# Muwa builds 49–50: layout and recognition contracts

## Navigation and player

The root content already respects the scene safe area. Bottom navigation keeps a
physical-screen clearance of 18 points on home-indicator iPhones (9 points on
home-button phones) and no extra margin on iPad. Build 49 used a 9-point margin
above the safe area and visibly raised the bar too far. Its 62-point height
and the 8-point mini-player gap share `BottomChromeLayout`; never add the system
bottom inset a second time. Player geometry uses the same anchor. Short landscape
layouts preserve the title clearance and full transport/action touch targets.

`NativeInteractionTests` checks the actual bar across Home, Library, Profile and
Player, plus real device rotation, queue dragging, playlist persistence, artwork
fill, buffering/pause and subtitle reader presentation. Long Arabic phrases wrap
and can scroll inside the rail; their drag must not page artwork or collapse the
player. Original text and audio time remain unchanged. Preparation checks compare
the reviewed source files byte-for-byte and reject duplicate implementations.

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

## Build 50 subtitle states

Public captions expose only coarse availability: available, processing, review,
unavailable. Unpublished recognition text and quality/job details remain private.
Empty rows defaulting to `captions_source=manual` are not owner-verified text.
The reader shows follow/translation controls and provenance only with content.
Without content the subtitle button opens a track-specific status sheet; no
placeholder is painted over the artwork. Dismissal restores the button state.
Existing manual captions and the worker quality gate remain protected.

## Design references supplied by the owner

- VoltAgent/awesome-claude-design (`8f746b5`): a catalogue of design references,
  not a native UI framework. Preserve Muwa's existing brand and native controls.
- Leonxlnx/taste-skill (`18dfc928`), redesign-existing-projects: targeted edits
  within the existing stack, legible hierarchy and explicit empty/error states.
- kylezantos/design-motion-principles (`4a9ca879`): restrained mobile motion,
  functional feedback and Reduce Motion. Existing player/rail springs are kept;
  no decorative transition or additional UI library is introduced for this fix.

These references inform the edits; their framework-specific recipes are not
copied into the SwiftUI application. The exact bar clearance and honest subtitle
states are covered by native UI and public HTTP regression tests.
