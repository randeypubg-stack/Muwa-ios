# Muwa startup — build 41

The reported black “Открываем Muwa…” screen came from `RootView` waiting
for `AuthManager.restore()` before mounting the app shell. The request could
wait on the network for up to the configured 30/60-second timeouts. A separate
full-screen brand animation also disabled hit testing and accessibility.

Home now mounts in the checking/guest/authenticated states using the existing
bundled or cached catalogue. Session restoration and catalogue updates remain
asynchronous. No unverified account or Premium entitlement is granted. A
missing/expired/offline session settles into guest mode; explicit sign-in,
registration confirmation and logout remain available. A short mark animation
runs in the Home toolbar, never above the whole app or its controls. Reduce
Motion, Low Power Mode and cancellation finish that animation immediately.

Checks added to the existing auth suite cover a held session, no session,
offline restoration, explicit sign-in during restore and stale response rejection.
The disposable Simulator launch fixture holds the auth service for 45 seconds,
requires the real Home shell to mount while auth is still checking, and uses
Vision OCR on the unmodified native screenshot to require Home/catalogue text.
Fixture services are injected after Release IPA/full-source packaging and do
not ship. The native MP4 is recorded by the existing Simulator recorder.

The system launch screen and OS process startup still exist. Simulator timings
include hosted runner/simctl overhead and are not measurements of physical
phone startup latency. This change removes intentional app/network waiting.

Validation:

- iOS run 100 (`37116765105`), native source
  `ed587eef47a3a66524ca590a39db34f3b3caba68`: Swift regression/auth checks,
  backend/PostgreSQL contracts, source scan, Release arm64 and Simulator build
  pass. Native screen capture steps pass on iPhone 16 Pro, iPhone 16 Pro Max,
  iPad Pro 11-inch (M4) and iPad mini (A17 Pro). CarPlay connects and produces
  an original 800×480 frame on attempt 2.
- The original phone review job failed in the recording wrapper after Home
  had mounted. Vision's driver diagnostic prefixed a valid Home JSON proof;
  the parser now keeps diagnostics and accepts exactly one successful proof.
  Encoder finalization also timed out in that run and the first independent
  attempt. These failures were preserved, not presented as successful videos.
- Independent launch run 4 (`37118354932`) passes both jobs, verifies all 51
  native inputs against compiled run 100, confirms Home while the auth service
  is held for 45 seconds, and saves a finalized native H.264 MP4. It is 1206×2622,
  25.395 seconds, with `ftyp`/`mdat`/`moov`; local ffprobe validates its stream.
  The mark remains inside Home; there is no full-screen intro or loading gate.
- Recorder signal checks cover ignored and blocked inherited signals. The child
  resets disposition and unmasks interrupt/terminate signals in its own process
  group. On successful run 4 the parent signal mask was empty; this does not
  establish that a blocked mask caused the earlier hosted recorder timeouts.
- Source scans pass. Final screenshot delivery has 70 original native PNGs:
  17 screens on each of four iOS sizes, pending-session Home and connected CarPlay.

The normal run's aggregate status remains failure because it contains the old
recording helper. The corrected independent launch is successful and uses the
byte-identical native app. Physical iPhone startup latency has not been measured.
Android runtime remains build 40; this is an iOS startup change.
