# Muwa Premium and subtitles

## Account access and gifts (2026-09-27)
Additive endpoint POST /_api/premium/access accepts JSON actions status, redeem, list, create, disable. Authentication uses the existing HTTP-only session; user ID is derived server-side. Apply premium-migration.sql before deployment. Existing authentication, uploads and v1 transcription contracts stay unchanged.

Premium is the union of verified StoreKit entitlements and a server account grant. The native manager resets account access/admin state on logout/account change, rejects old-account responses, refreshes on foreground and enforces expiry in memory. No email-based native unlock or server secret is embedded. A cold offline start cannot fetch the account grant; account-based access requires the session/server to be reachable after app launch.

Scoped premium_code_admins controls creation/list/disable independently of users.role. Codes have 96 random bits; only SHA-256 is stored. Full codes are returned once, so users must save/share immediately. A code grants 1–365 days, can serve 1–1000 different accounts and expires for activation after 1–365 days. Each account can claim it once. Existing finite gift time is extended; a permanent account does not consume a gift. Disabling a code does not revoke gifts already issued. Latest 100 codes are shown; creating is limited to 50/hour. Redemption is limited to 20 attempts/account/hour, including failed attempts. Server transaction locks serialize per-account extension and per-code capacity; unique redemption key ensures idempotency.

Integration checks: unauthorized/ordinary account denial, admin creation, simultaneous last redemption, normalized and repeated redemption, expiry extension, invalid/disabled/expired codes, preservation of redeemed access, permanent grant preservation, invalid bounds, expired account grant, attempt limit and foreign-origin protection. Temporary users and fixtures removed after tests. No real owner's session was impersonated; owner grant/admin checked directly in DB.

App Store review: custom unlock codes may conflict with Apple guideline 3.1.1. Current IPA implements the owner's explicit in-app gift request; do not represent it as approved for App Store. Apple subscriptions remain StoreKit-based. The user does not yet have Apple Developer.

## AI remains deferred
Original provider adapter: server-only OpenAI Whisper 1 timestamps + GPT-4.1-mini translation into RU/EN/TR/UZ/KK/FR. Real ASR previously failed due exhausted provider credit. Owner chose a rented worker, then deferred it for lack of budget. New automatic generation is therefore explicitly paused in subtitleV2Service; existing cached documents are still readable, subtitles are free. No paid AI calls/provisioning were made in this change. Provider and document unit specs pass but are not evidence of real recognition quality.
