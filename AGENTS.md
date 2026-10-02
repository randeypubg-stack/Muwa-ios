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
