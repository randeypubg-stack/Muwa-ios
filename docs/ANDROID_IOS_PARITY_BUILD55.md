# Android / iOS parity — Android Build 55

Reference: unchanged native iOS Build 54 (`c85a7dc`). Android retains application
ID `app.muwa.nasheeds`, Media3 playback/session, backend/auth contracts, download
storage and all existing preference keys. This is an Android release; iOS stays
at Build 54. No new reference mockup was selected or applied.

## Changes

- Four tabs in the same order: Home, Player, Library, Profile. Navigation stays
  visible in the expanded player; 62 dp bar, 58 dp mini-player, 8 dp gap. The
  existing physical-bottom anchor remains 18/874 clamped to 12–28 dp and clears
  Android system controls. Selection and drag use the same four slots.
- Shared glass panels, app-owned vectors (books, crown, captions, audio output),
  explicit text line heights, artwork placeholders, track rows,
  compact metadata, recommendation grid on tablets and collection frames match
  the iOS hierarchy. App branding is no longer used as a missing-track cover.
- The portrait artwork uses the measured controls height; short landscape
  windows compact the header and transport while keeping every action reachable.
  Player expansion respects reduced motion; the saved-position card has a cover
  and separate resume/open actions.
- White player transport, thin white scrubber, separate caption / queue / audio
  output controls, low-resolution subdued cover backdrop, full-frame crop, and
  matching favorite / playlist / timer / download / share actions.
- Queue opens over the player. Real Arabic captions first appear beside the
  artwork; tapping them opens the full reader. The reader has language / follow
  controls and a Done action back to the player. No pending-review placeholder.
- Published captions are authoritative; empty server results clear withdrawn
  text. Revision-specific offline/manual cache is retained on network failure.
  The client does not invoke the legacy transcription endpoint.
- Library uses the same hero, publication button, four category tiles and quick
  access. Existing local draft is reachable; submitted metadata persists in the
  existing Library owner under a new key. This is a local submission receipt,
  not a claim that moderation has finished.
- Profile follows the same identity, Premium and settings grouping. Android
  restores server-account access; it does not pretend to restore Apple purchases.

- Secondary screens share the iOS card hierarchy: sign-in/registration (including
  password confirmation), Premium benefit grid, and empty library/search states.
  Playlist detail can select/remove catalog tracks and rename through the existing
  Library store. Registration checks never submit a real account. Password input
  is ephemeral rather than saved to the Activity Bundle.

- One saved navigation history replaces the old flat route string. Search,
  authentication, nested Premium pages and playlist detail return to their actual
  origin; selecting a tab resets its detail history. A player that has no connected
  track cannot hide the catalog or select an empty player surface.

## Platform boundaries

Apple SF Symbols/system fonts, AirPlay and iOS system sheets are platform APIs.
Android uses equivalent symbols and system fonts, the Android output switcher
(API 34+) or its volume/Bluetooth panel fallback, and native Android sharing and
permissions. No Apple proprietary fonts or simulated system dialogs are bundled.

## Verification

Actual run IDs, runtime metadata, native captures and check results are recorded
in the delivery evidence. Do not treat compilation or a screenshot mockup as a
physical-device test. Keep the independent 62 dp / 18-of-874 UI assertions, plus
rotation, four-tab navigation, player actions, real caption seek/follow/RTL and
whole-row queue persistence checks. Rotation waits allow the temporary absence
of a Compose root during Activity recreation, but keep every layout assertion. Never change these assertions simply to
accept a shifted bottom bar.
