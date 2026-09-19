# Muwa Nasheeds — Native SwiftUI iOS

This repository builds the audited native SwiftUI version of Muwa Nasheeds.

- Bundle ID: `app.muwa.nasheeds`
- Version: `1.4.0`
- Build: `8`
- iPhone + iPad
- Portrait + landscape
- Native SwiftUI, no WebView/React/Capacitor

## GitHub Actions IPA

Every push to `main` builds a physical-device arm64 Release app on a macOS GitHub runner and packages it as:

`Muwa-Nasheeds-v1.4.0-build8-unsigned.ipa`

The IPA is **unsigned** because no Apple distribution certificate/provisioning profile is stored in this repository. It can be re-signed by a sideloading/signing service or later converted to a fully signed IPA after Apple Developer credentials are configured.

The workflow also validates the bundle id, version/build number, arm64 binary and uploads the Xcode build log.

Source archive SHA-256:

`e4527ee1540e8abbac69efc493eb4b87a83f5e3f687b407fa7ce53685f4bcd4a`
