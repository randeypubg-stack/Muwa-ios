# Muwa

Native iOS/iPadOS (SwiftUI, AVPlayer) and Android (Kotlin, Jetpack Compose, Media3)
clients for Muwa. Both use the existing Muwa backend and the same account service.

- App name: **Muwa**
- Bundle/application ID: `app.muwa.nasheeds`
- Version: `1.4.0`, build `37`
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
App name/asset updates preserve Bundle ID, backend contracts and user-data keys.
