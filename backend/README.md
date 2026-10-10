# Muwa backend on Beget

## Telegram catalogue import (3 October 2026)

The existing admin handler now supports `lookup-telegram-import` and
`import-telegram-track`. Imports create drafts, preserve existing accounts and
use the same private upload/verification path. Apply
`telegram-import-migration.sql` after admin/security migrations **before**
deploying the handler: normal saves/approvals also record verified fingerprints.
No new auth mechanism, Telegram credentials or ASR provider is added to clients.
See [the importer and deployment instructions](../tools/telegram-import/README.md).
The handlers and migration are deployed to the fresh Beget database. No live
Telegram channel import has occurred; channel access is a separate step.

Telegram lookup/import actions additionally require the single authenticated
user ID in `MUWA_TELEGRAM_OWNER_ID` on the server. An admin role alone never
grants import; missing or invalid configuration denies everyone. Other admin
actions retain their existing authorization. The owner-operated Beget setup
for @muwa144 is documented in the importer README; secrets stay outside Git
and are supplied to its non-root service using systemd credentials.

## Current deployment — 4 October 2026

The existing endpoint implementation runs as a standalone Node/Hono service on
Beget with PostgreSQL and private filesystem media. The owner explicitly chose
fresh data; no old Floot accounts or media were imported. Floot access/balance is
not a prerequisite. See [deployment and first login](../docs/BEGET-BETA-DEPLOYMENT.md).

`npm ci && npm run typecheck && npm run build` creates `dist/server.mjs`.
Required private server configuration: MUWA_DATABASE_URL, MUWA_PUBLIC_ORIGIN,
MUWA_STORAGE_ROOT and signing secrets; values stay on the VPS. Schema types are
generated from the actual database by `npm run schema:generate`.

## Reproducible checks
Run `npm ci && npm test` in this directory for provider/document tests without
paid API calls. Setting `MUWA_TEST_DATABASE_URL` additionally runs transaction
checks on a **new disposable PostgreSQL database** (it creates fixture tables
and truncates Premium data). Never point this variable at production. The test
runner supplies fixture auth adapters only in its temporary test tree.

## Account access and gifts (2026-09-27)
Additive endpoint POST /_api/premium/access accepts JSON actions status, redeem, list, create, disable. Authentication uses the existing HTTP-only session; user ID is derived server-side. Apply premium-migration.sql before deployment. Existing authentication, uploads and v1 transcription contracts stay unchanged.

Premium is the union of verified StoreKit entitlements and a server account grant. The native manager resets account access/admin state on logout/account change, rejects old-account responses, refreshes on foreground and enforces expiry in memory. No email-based native unlock or server secret is embedded. A cold offline start cannot fetch the account grant; account-based access requires the session/server to be reachable after app launch.

Scoped premium_code_admins controls creation/list/disable independently of users.role. Codes have 96 random bits; only SHA-256 is stored. Full codes are returned once, so users must save/share immediately. A code grants 1–365 days, can serve 1–1000 different accounts and expires for activation after 1–365 days. Each account can claim it once. Existing finite gift time is extended; a permanent account does not consume a gift. Disabling a code does not revoke gifts already issued. Latest 100 codes are shown; creating is limited to 50/hour. Redemption is limited to 20 attempts/account/hour, including failed attempts. Server transaction locks serialize per-account extension and per-code capacity; unique redemption key ensures idempotency.

Integration checks: unauthorized/ordinary account denial, admin creation, simultaneous last redemption, normalized and repeated redemption, expiry extension, invalid/disabled/expired codes, preservation of redeemed access, permanent grant preservation, invalid bounds, expired account grant, attempt limit and foreign-origin protection. Temporary users and fixtures removed after tests. No real owner's session was impersonated; owner grant/admin checked directly in DB.

App Store review: custom unlock codes may conflict with Apple guideline 3.1.1. Current IPA implements the owner's explicit in-app gift request; do not represent it as approved for App Store. Apple subscriptions remain StoreKit-based. The user does not yet have Apple Developer.

## Local automatic recognition
On 7 October 2026 the owner resumed subtitle recognition on the existing Beget
server. [The local worker](../tools/local-asr/README.md) runs full Whisper large-v3
with CPU int8 inference in a durable, sequential PostgreSQL queue. Verified
catalog uploads, Telegram forwards and approved submissions queue automatically.
Audio/publication never waits for ASR. Existing manual/cached captions remain
available; changed audio, revoked leases and manual revisions reject stale
results. Intentionally cleared manual captions are also preserved.

Confident original AR/RU/EN output becomes ordinary subtitles with acoustic word
timings. Uncertain results remain in the owner's editor for review; translations
are not fabricated. New local inference was checked on complete nasheeds: one
71.7-second recording produced 14 lines for review, and another 145.8-second
recording produced 24 automatic lines/109 acoustic words delivered by the native
caption endpoint. The latter took 355.97 seconds on the 2-core/4-GiB VPS. These
measurements verify operation, not word accuracy against human-reviewed lyrics.

The previous paid OpenAI Whisper/GPT adapter remains paused in subtitleV2Service;
its cached documents remain readable. It is separate from the enabled local
upload worker. No paid ASR/translation requests are made.

## Security deployment

Admin, security, Premium, subtitle v2, Telegram and local ASR migrations are applied in the
fresh database. Existing authentication and handler contracts are preserved.
Runtime additionally enforces owner-only beta access and disables registration.
Production API/storage smoke passed with a trusted TLS connection; unit checks
alone are not presented as production evidence.

`npm run test:runtime` requires MUWA_TEST_DATABASE_URL pointing to a loopback
**muwa_audit** database; it refuses production and resets only that test schema.
Set MUWA_AUDIT_STORAGE_BASE to a writable disk with more than 5 GiB free, matching
the real upload disk reserve. The earlier transaction suite also uses muwa_audit.
Neither test command may be pointed at production.
