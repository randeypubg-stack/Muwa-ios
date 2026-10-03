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

Validation status: local source registration, fixture generation, Python syntax
and recorder signal checks passed; Release and macOS Swift/runtime review are
pending the build 41 GitHub Actions run.
