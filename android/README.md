# Muwa native Android review

The app uses Kotlin, Jetpack Compose and Media3. Its application ID remains
`app.muwa.nasheeds`; compile/target SDK remain 35. Running on a newer OS and
raising target SDK are different changes, so this review does not silently alter
the app's platform behavior.

The workflow requests Google's stable API 37.2 image
`google_apis_ps16k;x86_64` on three native display sizes, plus API 35 compatibility
on the large phone size. Google's platform and image indexes confirmed API 37.2
as the latest stable platform on 2026-10-04. Preview codenames, beta/canary paths
and SDK extensions are excluded even if listed on channel 0.

- Platform index: https://dl.google.com/android/repository/repository2-3.xml
- Image index: https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml
- Stable command-line tools 23.0: https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip

The command-line archive was checked against Google's recorded size
181052239 bytes and SHA-1 `e025545c62a8e64c7559119566a569fb1dec5f60`.
CI independently checks the official checksum and compares installed files with
the original archive. Profile discovery and AVD creation use the same pinned SDK
installation. Its catalog includes `pixel_10_pro_xl` and `pixel_tablet`; this
catalog check proves profile availability, not an application test result.

The selected profile comes from the installed `avdmanager` catalog. Display size
and density overrides stay explicit. A phone profile with a larger display does
not become a verified physical tablet, and an emulator profile does not prove
that Muwa ran on a physical Pixel.

Each screenshot and launch manifest records the booted AVD, hardware profile,
system-image directory, Android release/codename/SDK, emulator version, page
size, physical display geometry, overrides and source configuration. Screenshots
must retain the actual configured pixel dimensions and orientation. Successful
review requires a complete manifest and a successful CI job; requested matrix
labels alone are not evidence that a device booted or the app worked.

On a cold emulator, `sys.boot_completed=1` can precede responsive Binder services.
The bounded readiness check requires three consecutive package/window/settings
checks with confirmed zero animation scales before tests start. Persistent
failures remain failures and retain boot diagnostics. Native cold launch and
reduced-motion checks still require actual Home content; optional launch video
is an independent, strict workflow-dispatch option.

Android 17 removed the reflective `InputManager.getInstance` method used by the
older Espresso dependency. Instrumentation uses the stable AndroidX Test release
set: Espresso 3.7.0, runner 1.7.0 and JUnit 1.3.0. Google's release notes explicitly
record the switch to `getSystemService`. These are test APK dependencies; the
application's Compose dependencies and SDK target stay unchanged. Functional
navigation and queue assertions are retained.

The full player shares the Activity's edge-to-edge viewport instead of opening a
second Dialog window. Its background covers the screen while controls consume
safe-drawing insets once. Text and Queue stay below a scrollable player body and
above the system navigation bar. Short landscape controls can scroll without
hiding those actions. Instrumentation checks the full viewport and unclipped
button bounds against the real system-bar/cutout insets in both orientations,
then opens Queue, opens Subtitles and closes/reopens the player through native
controls. Screen review also captures the player with the enlarged system font.

Release evidence: https://developer.android.com/jetpack/androidx/releases/test#espresso-3.7.0

Run the evidence regression checks with:

```sh
python3 tests/AndroidReviewDeviceChecks.py
```
