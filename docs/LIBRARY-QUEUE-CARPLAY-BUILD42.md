# Muwa 1.4.0 build 42

The playlist destination shown by the owner now keeps Muwa's ambient background.
Its empty state has one creation action. Playlist cards use real cover art, and
creation uses an adaptive native sheet. Existing navigation titles supply Russian
back labels; the system back button and edge gesture remain owned by NavigationStack.
Playlist screens, artwork, creation and track selection are separated into focused
source files. Preparation replaces base files and registers every source once.

Playlist detail offers native selection from the same catalogue. Adding tracks
uses LibraryStore's existing deduplication and persistence. Playing a playlist
uses its actual tracks as the queue. Existing download, queue and removal actions
remain available; Premium feature gates remain disabled during functional beta.

QueueView uses native List.onMove. The system lifts the entire row and supports
reordering and scrolling; the former String draggable and copy badge are removed.
VoiceOver retains move-up/move-down actions. Visible-list offsets are mapped back
to saved queue IDs, preserving unavailable tracks and their positions. Moving a
row only changes the persisted queue, and never starts or changes playback.

CarPlay uses Apple's image-row and list templates, with a cover shelf and a
collection section. Track and playlist rows now show artwork. The same decoded
artwork cache coalesces requests, equal snapshots avoid unnecessary list rebuilds,
and disconnect/list changes cancel stale image updates. Tabs, alerts and Now Playing
remain Apple's automotive controls, as required by the audio entitlement.

Validation: native run 104 (`37126355145`, source `7228cac76c9608f9ad204733b4ec04efe4843716`)
passed Release/Simulator compilation, source scanning, backend contracts, all four
screen sizes and both real XCUITest interactions. Queue drag changes the row order,
keeps the current track paused and persists after restart. Create/add/restart/native
back navigation also passed. Startup review proves Home is visible while the session
request remains pending for 45 seconds. This is a Simulator check, not a physical
startup latency or FPS measurement.

CarPlay's real scene and 800×480 screenshot passed in run 103 (`37125918675`).
All 56 native inputs in that source match run 104 byte for byte. The first CarPlay
capture in run 104 and its first rerun did not enter Muwa after the launcher click;
the aggregate run remains failure. Those diagnostic frames are not presented as
successful screenshots. The capture helper now uses a held pointer press and
bounded retries that require fresh native launcher recognition before each input.
Independent capture run 8 (`37128717434`) uses the compiled run-104 source;
its build/signature/source checks passed, but all three launcher presses left
the external display on the launcher and no Muwa scene proof was written.
It therefore correctly failed instead of accepting that display as Muwa.
The accepted CarPlay frame remains the connected scene from run 103. Capture
automation is still intermittent on hosted Simulator; physical CarPlay remains
an outstanding device/provisioning check.

On 3 October the Floot publish snapshot reports `published: false`. Public catalogue
and CDN requests fail, and the Floot daily action limit blocks inspection/restoration
until 4 October 00:00 UTC. This is a separate live-service blocker, not a successful
production media validation. No backend/account/DB/hosting configuration was changed.

Simulator UI review uses a generated local PCM file paused in the real AVPlayer.
An isolated HTTPS URLProtocol response checks the existing artwork decoder/cache and
preblur against AppMark bytes. Track views still use their actual artwork URLs and
show normal fallback symbols while CDN assets are unavailable. These controlled
fixtures are injected after the Release IPA and full source are packaged. Each
capture also writes `live-assets-status.json`; successful UI review does not claim
that production streaming, artwork or authenticated APIs are available.
