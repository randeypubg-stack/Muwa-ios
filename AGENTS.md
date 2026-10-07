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
