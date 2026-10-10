# Muwa remote control panel

Live route: https://93.188.187.96/admin. This is the existing Muwa panel adapted
for the fresh Beget deployment chosen by the owner on 4 October 2026. It shares
canonical contracts with `../backend`; it is not a browser wrapper for the apps.

Install shared contract dependencies first: `cd ../backend && npm ci`. Then run
`npm ci && npm run build` in `admin-panel/` to typecheck and create the nginx `dist/` bundle.
React/Vite provide the panel runtime, existing controls and screen logic are
retained. All API/media requests use the same HTTPS origin and HttpOnly session.
No third-party fonts, embedded credentials or separate account service are required.

First owner login is described in [deployment instructions](../docs/BEGET-BETA-DEPLOYMENT.md).
The one-time setup link remains in a private root file on the VPS. Public
registration is disabled during the owner-only beta. Published catalog entries,
audio and captions are available without login; drafts and admin actions remain private.
Server-side user role is checked on every admin request, including uploads.

- Audio/cover upload uses private signed PUT tickets on NVMe, then server-side
  file validation; maximum audio 100 MiB, cover 10 MiB.
- New tracks can be drafts or published. Archive removes discovery entries
  without replacing track identity. Revision conflicts return 409.
- Manual Arabic/Russian/English timed captions support preview, seek and JSON
  import/export; bounds and overlaps are validated. Replacing audio clears timing.
- Local original-language ASR queues new uploads automatically, including Telegram
  forwards. The caption editor shows progress, saved results and quality warnings;
  the owner can retry and review text. Recognition never blocks upload/publication,
  overwrites manual edits or restores intentionally cleared manual captions.
- Publications preserve the audio/cover/submission.json readiness protocol.
- Committed catalog/moderation mutations write the existing audit journal.
  Passwords, session tokens and signed file tickets are not journaled.
- Native iOS build 43 / Android build 41 use the Beget catalog with authenticated
  audio and covers. Demonstration tracks are isolated to review/test fixtures.

The old `backend/admin-seed.sql` is historical and was not applied to this fresh
beta. No old accounts, Premium grants or media were imported. Backend checks cover
real PostgreSQL transactions and the full HTTP login/upload/publication chain.
