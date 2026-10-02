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
- Subtitle development is deferred by the owner on 2 October 2026. Preserve
  existing manual/cached captions and the future requirement for automatic
  nasheed transcription after upload, independent of the chosen ASR provider.
  Do not activate paid recognition or make upload/publication depend on it now.
- The next hosting direction is a closed beta on rented infrastructure. Follow
  `docs/CLOSED-BETA-HOSTING.md`; preserve existing accounts, track IDs and API
  contracts through a staged migration rather than creating an unrelated backend.
  Initially only the owner tests. Size the initial hosting for the planned
  10,000 total registered users with headroom, not for a small beta group or
  10,000 simultaneous listeners; validate capacity with load tests.
