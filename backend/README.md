# Muwa AI subtitles v2

Additive Floot backend. Legacy `/_api/transcribe` is unchanged.

New authenticated POST routes: `/_api/subtitles/original` and `/_api/subtitles/translate`, plain JSON. Sources are limited to the application's public CDN audio paths, at most 10 minutes. Original transcription detects language and returns immutable phrase IDs and optional estimated word times. Translations reference the stored original and never rewrite timings or original text. Missing/malformed word times use phrase-level highlighting, never interpolated word offsets.

AI provider: existing Floot AI Gemini 3.5 Flash. Requires available Floot AI credits. Current live test on 2026-09-23 returned `OUT_OF_CREDITS`; transcription accuracy and successful translation are NOT yet verified on real audio. Do not claim otherwise or ship fixtures as results.

Schema migration is additive. Cached results are shared for public audio. Charged generation requires a signed-in user; a database lease coalesces duplicate requests, and an atomic daily counter caps new operations at 20 per user. Subtitles are a standard app feature and are not Premium-gated. New AI generation still requires a signed-in user for abuse control, but there is no server-side Premium/payment entitlement check.

Deployment: write the helper and endpoint files to the existing Floot project, apply migration.sql, run helper validation tests and real authenticated audio/translation checks, then publish the backward-compatible changes. No API secrets are in native code.

Provider timing is estimated, not certified forced alignment. Singing, overlapping voices, noise and unfamiliar languages still require accuracy evaluation. A missing/unrecognized phrase remains a gap. The app shows automatic recognition status and preserves the original if a translation fails.


Build 31 UI note: the compact player uses a transparent subtitle rail to the right of a slightly reduced cover. The rail animates only subtitle lines vertically; the player background, transport controls, colors and bottom navigation remain unchanged. If AI recognition is unavailable, the native app falls back to the legacy subtitle source when possible.
