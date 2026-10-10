# Muwa

Native iOS/iPadOS (SwiftUI, AVPlayer) and Android (Kotlin, Jetpack Compose, Media3)
clients for Muwa. Both use the same Muwa backend and account contracts, now hosted on Beget.

- App name: **Muwa**
- Bundle/application ID: `app.muwa.nasheeds`
- Version: `1.4.0`; iOS build `43`, Android build `41`
- Brand assets: the supplied silver-blue logo in `branding/`, verified by SHA-256
- Cold launch: short native reveal, light sweep and fade; respects reduced animation

The iOS workflow verifies the immutable native source archive, applies
`native-patches/` and `branding/`, then builds an arm64 unsigned IPA and complete
Xcode source archive. The Android workflow builds debug/release APKs and runs unit,
Lint and emulator checks. Separate jobs capture iPhone, iPad and available CarPlay
displays; native launch-motion recordings are included in review artifacts.

The device IPA is unsigned. Android debug APKs are signed with a development key;
release APK signing and store billing require the appropriate release configuration.
CarPlay configuration and its Apple-approved provisioning requirement are described
in [docs/CarPlay.md](docs/CarPlay.md).

The immutable iOS base stays at:
`f07bce80d5b9b39583a8bce19f3e3b71caed205332649f13ccb45a8b28997f84`.
It is tracked in `source-base/MuwaNativeBase.zip`; CI does not need a CDN source download.
App name/asset updates preserve Bundle ID, backend contracts and user-data keys.

Palette, typography, motion and backgrounds are separated from screens and data
services. See [Architecture](docs/ARCHITECTURE.md) and
[Build40 design review](docs/DESIGN-BUILD40.md). Both native clients use three soft
ambient lights, compact catalog collections and a shared persistent queue with
animated controls. Reduced motion and power-saving modes stop background movement.

Premium restrictions remain disabled for feature testing. Local Whisper large-v3
recognition now runs after uploads on Beget; see [the worker](tools/local-asr/README.md).
Paid AI providers remain disabled. Production StoreKit/Play Billing,
CarPlay provisioning and physical-device validation still require completion.

The owner permits a public repository. CI scans source history and archives for
secrets. On 4 October 2026, the owner chose a fresh database and catalog without
importing old Floot records. The existing backend and admin handlers run on Beget
with private media storage and trusted HTTPS: https://93.188.187.96/admin.
Floot is no longer required to build or run this beta; its old project is untouched.
See [the deployment and first-login instructions](docs/BEGET-BETA-DEPLOYMENT.md).
Client build numbers above identify the updated source; CI results establish
whether their installable artifacts are ready.

7 October 2026 — build 47 player fixes
------------------------------------
Home retains native large-title collapse, without the removed toolbar mark;
iOS 26+ scroll-edge blur is hidden. Home and collection playback supply the
actual collection as the queue, so next/shuffle have more than one item on a
fresh catalogue. Both subtitle buttons share one state and reader: published
Arabic originals, word timings when available, and already saved translations.
Local captions never initiate paid provider calls. MP3/M4A/WAV downloads inspect
the actual container, validate a correctly named staged file and persist its
format for offline playback across restarts. Existing offline keys remain valid.
The retired toolbar launch view/state and its Xcode registration are removed.
Regional Arabic ASR routing and original preservation are tested independently
of accuracy; representative dialectal nasheed lyrics still need human evaluation.
