# Muwa remote control panel

Live route: https://muwa-app.floot.app/admin

The panel is part of the existing Floot project
`20d2f317-3710-4331-80ee-ea6072056928`. These files mirror the changed Floot
pages/components/auth helper. They are an overlay for that project, not a second
frontend/backend or an independent deployment. Shared seeded controls and the
existing database/auth adapters stay in the Floot project. Server implementations
are in `backend/helpers/admin*` and `backend/endpoints/admin`/`catalog`.

- Use the existing Muwa account. Server checks `users.role = 'admin'` on every
  panel request. The owner explicitly selected their existing account in the conversation.
- Audio and covers upload directly to Floot storage; files are verified before
  saving. Maximum audio 100 MiB, cover 10 MiB. No paid server was provisioned.
- New tracks start as drafts unless Published is selected. Archive removes a
  track from discovery without deleting listener IDs, queues or downloaded files.
- Metadata, status, subtitles and moderation use revisions: a stale edit returns
  HTTP 409 and must be reopened after refresh.
- Subtitles support original Arabic, Russian and English with timed lines,
  listening preview, seek, JSON import/export. Times must be ordered, non-overlapping
  and within the audio duration. Replacing audio clears old timings.
- Automatic ASR is paused because the existing provider lacks credits. The panel
  never starts a paid recognition request. Existing legacy/v2 endpoints are retained.
- Publications use the original private audio/cover/submission.json protocol.
  Refresh scans final ready markers in bounded batches; a presigned draft alone
  is not accepted for moderation. Approval copies files via the administrator's
  browser to public storage and atomically creates one catalogue entry.
- All committed catalogue and moderation changes write the same database journal.
  Session tokens, passwords, private URLs and PUT credentials are not journaled.
- Public endpoints: GET /\_api/catalog/tracks and
  GET /\_api/catalog/captions?trackId=...; only published data is returned.
- Native build 38 consumes these endpoints. Older builds with a bundled catalogue
  need an app update. The public feed is cached for 30 seconds.

Migration: `backend/admin-migration.sql` (additive, existing DB). Seed:
`backend/admin-seed.sql` copies the original seven IDs with ON CONFLICT DO NOTHING.
The migration intentionally grants no roles or Premium entitlements.

Validation: Floot full typecheck + Jasmine validation/provider tests; disposable
Postgres integration tests (`backend/README.md`); authenticated live API/storage
checks; native registration, Android build/unit/lint and GitHub iOS CI.
