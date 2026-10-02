# Muwa CarPlay

CarPlay uses Apple's audio templates and the same PlayerManager, LibraryStore,
DownloadManager, queue and MPRemoteCommandCenter as iPhone. No web content is used.

Five native tabs show the catalog, favorites, downloaded audio, playlists and recent
listening. Selecting a track uses that list as the playback queue. Now Playing offers
favorite, shuffle and repeat actions; its Up Next button opens the shared queue.
System playback, seek, next and previous buttons use the existing remote commands.
Playback errors offer Retry. List updates preserve the selected tab and navigation.
Disconnecting and reconnecting release observers without stopping iPhone playback.

The existing scene manifest selects `CPTemplateApplicationScene` and its delegate
for the CarPlay role. Phone scenes remain owned by the existing SwiftUI app.

`MuwaCarPlay.entitlements` requests `com.apple.developer.carplay-audio`, and the
source preparation script provides an opt-in signing setting in both Xcode configurations. It also adds
the CarPlay scene while preserving any existing phone scene configurations.
This file requests a capability; it is not evidence of Apple approval.

Physical installation requires Apple's CarPlay Audio approval and a provisioning
profile for `app.muwa.nasheeds` with that entitlement. The normal device IPA stays
unsigned. For an approved development/distribution profile, pass
`MUWA_CARPLAY_ENTITLEMENTS=MuwaCarPlay.entitlements` to xcodebuild (or set that
user-defined build setting in Xcode), then sign with the approved profile to test
on a car/head unit. The setting is empty by default, so normal iPhone signing
does not suddenly require an unapproved CarPlay capability. An ordinary
sideloading profile may not include the CarPlay entitlement.

CI builds a separate Simulator fixture using Xcode signing with the CarPlay
entitlement; the phone review and unsigned device IPA are unaffected. The signing
identity is local ad-hoc (`-`), not an Apple-approved distribution identity.
`tests/capture_carplay.py` verifies the signature and the actual entitlement in the
executable. Xcode stores Simulator grants in a Mach-O section, so an empty code-signature
entitlement dictionary does not mean those grants are missing. The script tries to open
Simulator's CarPlay external display, and captures that display only after Muwa's
CarPlay scene reports a connection. If the runner cannot expose or connect the
external display, `build/previews/carplay/status.json` records the reason. A missing
capture is never replaced by a mockup or a phone screenshot.
The script selects Muwa from the real CarPlay launcher using on-runner Vision
text recognition and a Simulator mouse click; opening the display alone does
not select an app. The original launcher frame is retained for diagnosis.
An unconnected external display is retained as a diagnostic image only; it is
never marked as a successful Muwa CarPlay screenshot.

Before distribution, test track selection from each tab, offline playback with the
network disabled, queue advancement, favorites updated on either screen, interruption
and route changes, playback retry, and car disconnection/reconnection on real hardware.
