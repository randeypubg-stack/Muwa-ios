# Muwa development rules

Правило владельца: редактируем существующий код, а не дописываем вторую
реализацию поверх первой.

- Edit the existing implementation of a feature. Do not append a second class,
  handler, state owner or alternate code path to override the first one.
- Before changing a feature, find its callers and the source file actually used
  by the build. Remove superseded code and update callers in the same change.
- `native-patches/` contains replacements for files in the immutable iOS base.
  Preparation must replace each original file and register it once in Xcode;
  never compile both the original and replacement implementations.
- Keep the app name Muwa, application ID `app.muwa.nasheeds`, existing backend,
  account contracts and persisted user-data keys.
- Preserve intentionally supported compatibility, migrations and staged feature
  flags. A text search alone is not proof that a public or framework callback is
  unused.
- Verify changed behavior with suitable checks. State clearly what was tested
  and what still requires backend deployment or a physical device.
- The owner approved the Build 50 navigation position on 9 October 2026.
  Preserve the iPhone 17 Pro reference: 18 pt physical-bottom clearance on an
  874 pt window, 62 pt iOS bar height and 8 pt mini-player gap. Adapt only the
  outer clearance proportionally to the current window, within 12–28 pt/dp,
  while respecting system controls. Keep one geometry owner per platform;
  tabs, playback state, captions and text size must not choose separate offsets.
  Do not change this approved geometry without a new explicit owner request.
  Preserve its golden geometry tests and actual rotation/tab regression checks.
- On 7 October 2026 the owner resumed automatic subtitle recognition on the
  rented server. Use a local worker; preserve manual/cached captions and keep
  upload/publication independent of recognition. Do not activate paid providers
  or promise maximum accuracy without checking actual nasheed recordings.
- The hosting direction is a closed beta on rented infrastructure. On 4 October
  2026 the owner explicitly chose a fresh Beget database and catalog: previous
  Floot accounts, Premium grants, captions and media need not be imported. Leave
  that project untouched. Adapt the existing backend and panel, preserve native
  application IDs and API contracts, and do not create an unrelated application.
  Initially only the owner tests. Size the initial hosting for the planned
  10,000 total registered users with headroom, not for a small beta group or
  10,000 simultaneous listeners; validate capacity with load tests.
- Device verification must include the latest available stable iOS/iPadOS and
  Android runtimes, alongside meaningful compatibility coverage. The owner
  specifically requested iPhone 18 Pro Max and iOS 27 on 4 October 2026.
  Record the actual simulator device type, OS/runtime, SDK/toolchain and capture
  dimensions. Screen-size overrides do not establish testing on a physical model;
  never relabel an older runtime or mockup as the requested device.
- The owner reported a navigation/subtitle regression in build 48 on iPhone 17 Pro
  / iOS 27.2. Safe-area changes must check the bottom bar, mini/full-player morph,
  every main tab and short landscape layouts. Subtitle changes must check long
  Arabic phrases, scrolling, artwork paging and reader open/close. Record actual
  tested runtimes and preserve the regression checks; see
  `docs/BUILD49_LAYOUT_AND_RECOGNITION.md`.

- Canonical iOS files mirror the Xcode tree under `native-patches/Sources`,
  `Resources` and `Configuration`. Generate the complete project only through
  `scripts/assemble_ios.py`; do not edit a packaged/generated copy as a new source.
- Typography, animation policy and shared design tokens live in each platform's
  design/theme folders. Feature modules own presentation; existing models/hooks
  remain single state owners. Respect the folder map in `docs/ARCHITECTURE.md`.
- All local recognition output remains a private ASR draft until explicit owner
  review/save. Model confidence cannot publish lyrics. Proposed design reference
  mockups are unselected and must not be applied without an owner design choice.
- Portable exports must use a clean committed Git tree and current-branch bundle,
  include restore instructions, and verify ZIP integrity and offline restoration.
  Never include runtime credentials, signing keys, Telegram sessions or build
  caches. A source archive is not a backup of live PostgreSQL/media.
