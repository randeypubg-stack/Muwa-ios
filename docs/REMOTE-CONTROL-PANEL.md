# Muwa control panel — 2 October 2026

Live: https://muwa-app.floot.app/admin
Owner: the existing Muwa account explicitly selected by the owner (server role admin).
Same Floot project, PostgreSQL database, account/session contracts and app IDs.
No new paid infrastructure or ASR provider was activated.

Implemented: real server-backed catalogue, audio/cover uploads, metadata and status
editing, private submission moderation, Arabic/Russian/English timed subtitles,
JSON import/export with audio preview/seek, and a database audit journal. Revisions
protect simultaneous edits; uploads are verified and single-use plans are claimed
in the same transaction as publication. Drafts and their captions are private.
Original audio replacement invalidates timings and stale offline-source matches.

Native build 38 reads the public catalogue and manual captions. It keeps a valid
snapshot offline, retains saved listener IDs/metadata, accepts intentional empty
catalogues and leaves current playback running. Legacy transcripts remain a fallback
for the original static tracks without edited captions. ASR is still paused.
Older installed builds with a bundled catalogue require an update.

Verification:
- Floot full typecheck: clean. Validation and ASR document/provider specs: passed.
- 30 backend specs passed against disposable PostgreSQL 16 using the same postgres-js
  driver as Floot, including races, replay, expiry, permissions and JSON shape.
- Live guest 401 / normal account 403 / foreign-origin mutation 403 verified.
- Actual MP3 storage upload, draft persistence, subtitles and audit journal verified.
- Real private audio + submission.json marker reached moderation and was rejected.
- Browser login, catalogue and editors verified; no uncaught JS errors or horizontal
  overflow at 1440, 820, 393 and 412px. Captures use a temporary QA account.
- The workspace's egress proxy removes Content-Length on S3 PUTs. For the browser
  upload check only, the identical file/URL/headers were forwarded through the Floot
  compute VM to the real S3 service; the application contains no such proxy or mock.
- iOS CI 37005034519: SUCCESS (Release arm64, checks, 4 phone/tablet review jobs,
  CarPlay review). This validates build/fixtures, not physical CarPlay entitlement.
- Android CI 37005427223: SUCCESS (build/unit/lint + 3 device review jobs).
- Local Android debug/release/unit/lint and Xcode registration idempotency passed.

Remaining housekeeping:
The provider hit its 100-actions/day tool limit during final QA cleanup. It resets
3 October 2026 at 00:00 UTC. The production publish completed before this refusal.
The QA track was archived through the live console API and is absent from the
public catalogue (the 7 original tracks remain public). Known QA sessions were
logged out. The temporary QA account (id 9), its journal/archived records and small
storage files still require deletion after reset. Only the owner's real account
should remain admin after this cleanup; do not grant Premium or change owner data.
The exact scoped SQL and storage key list are in the private workspace review
folder `/workspace/artifacts/Muwa-admin-review/`; that folder contains test
credentials and MUST NOT be committed or included wholesale in downloadable ZIPs.

Screenshots ZIP includes PNGs and a description only. Native IPA is unsigned and
must be signed using the user's existing identity. Android CI offers a debug APK
and an unsigned release; a production Android signing key is not configured here.
