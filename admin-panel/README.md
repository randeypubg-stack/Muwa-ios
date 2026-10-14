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
- Published catalog entries, audio, covers and checked captions are available
  to guests as well as signed-in listeners. Drafts, recognition documents and
  management actions require the existing authenticated owner/admin access.
  Demonstration tracks are isolated to review/test fixtures.

The old `backend/admin-seed.sql` is historical and was not applied to this fresh
beta. No old accounts, Premium grants or media were imported. Backend checks cover
real PostgreSQL transactions and the full HTTP login/upload/publication chain.

## Code map

- `pages/` and `components/AdminWorkspace.tsx`: routing and the existing access
  gate. Authentication, iframe protection and admin-role checks stay here.
- `features/workspace/AdminConsole.tsx`: the workspace shell and section views.
  `useAdminWorkspace.ts` owns filters, server queries, refresh and mutation
  feedback; each editor keeps only its own unsaved form state.
- `features/catalog/TrackEditor.tsx`: track metadata, private upload tickets and
  explicit acceptance of a suggested title.
- `features/captions/CaptionEditor.tsx`: audio preview, timed Arabic/Russian/
  English text, local recognition drafts, JSON import/export and explicit save.
- `features/submissions/SubmissionReview.tsx`: preview and owner approval or
  rejection of a submitted recording.
- `components/`: shared controls and their CSS Modules. The unchanged
  `AdminWorkspace.module.css` owns the coordinated shell/editor styling so the
  split does not change selectors, responsive breakpoints or appearance.
- `styles/tokens.css`: colors, spacing, surfaces, radii, shadows and layers.
  `styles/typography.css`: font stacks with system fallbacks.
  `styles/motion.css`: shared animation durations. `base.css` imports these and
  retains the global viewport rules; fonts are not downloaded from a CDN.
- `helpers/adminPresentation.ts` and `helpers/mediaUpload.ts`: presentation
  labels/formatting and browser upload/audio metadata utilities.
- API clients, schemas and authorization remain canonical in `../backend/`;
  the panel imports their existing contracts instead of copying them.
