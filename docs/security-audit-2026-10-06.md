# Muwa security review — 6 October 2026

Scope: canonical iOS patches and immutable base, Android code, backend/session/roles,
Premium, publications/catalog/storage, admin panel, Telegram importer, dependencies,
Git history and read-only inspection of the owner's Beget host. Existing files are
edited in place. Paid ASR stays disabled; ordinary subtitles and beta feature access
are preserved. No production database reset or attack against unrelated hosts.

## Changes

- Reject login passwords exceeding bcrypt's 72 UTF-8 byte limit. An actual HTTP
  regression verifies a 72-byte password succeeds and its longer aliases fail.
- Permit Android media-session connections only from our UID or OS-trusted clients.
  Export remains enabled for notifications and trusted system/Bluetooth controls.
- Bound offline transfers to 100 MiB and three concurrent downloads; reject incomplete,
  empty and undecodable media before publishing it. Android retains a disk reserve.
- API requests and signed uploads no longer follow redirects. iOS storage uploads
  use a cookie-free session even on the API host. Media redirects stay available
  for the catalogue's signed-storage delivery and cannot downgrade Android TLS.
- Bound native JSON/artwork response reads to 10 MiB, including unknown-length bodies.
- Constrain ffprobe/ffmpeg input demuxers to MP3/WAV/MOV and protocols to file/pipe
  before probing. Reject excessive embedded-image dimensions and limit allocations.
  A disguised HLS file cannot contact a loopback HTTP target in the regression test.
- Fix my Telegram setup wizard: interruption or failed reconfiguration restores the
  previous private configuration and running watcher. Configuration writes are atomic,
  mode 0600, with temporary files cleaned up.
- Update React Router from 6.30.6 to 7.18.4; known dependency advisories disappear
  from the panel audit. Remove one unused login-cleanup result variable.

## Evidence at review time

- Backend: typecheck/build passed; 56 service specs and 38 actual HTTP checks passed
  against a disposable PostgreSQL database. Production DB was not reset.
- Importer: 19 tests passed using real ffmpeg/ffprobe, including network isolation,
  cancellation rollback, duplicate identity and upload-cookie isolation.
- Gitleaks: no findings in all local Git refs or tracked working source, including
  nested archives. This is evidence from a scanner, not a guarantee that no secret exists.
- npm audit: zero production advisories for backend; zero panel advisories after update.
- OSV query: no advisories returned for all 81 resolved Android release-runtime
  Maven coordinates, including BOM-selected/transitive dependencies. Pinned httpx
  and Telethon coordinates also returned no advisories.
- Android build 46: debug/release compilation, seven unit checks and lint passed.
- Build 46 mobile changes require new binaries. Earlier build-45 IPA/build-42 APKs
  do not contain these fixes. CI results and deployment are tracked separately;
  this document does not claim pending checks passed.

## Server and remaining limits

Verified: PostgreSQL and API bind only to loopback, public firewall exposes 22/80/443,
Fail2ban is active, TLS 1.2/1.3, query-free access logs, login throttling and eight
connections per IP. API runs as muwa with a read-only system, private temp directory,
resource caps, zero Linux capabilities, disabled core dumps, private devices, protected
kernel settings/logs/clock, and root-owned mode-0600 environment. Telegram runs as a separate
non-login UID with a private state directory and systemd credentials.

Root SSH password login is still enabled. It must be replaced after a separate SSH-key
login has been verified; disabling it now could lock the owner out. Root remote-tool
access remains privileged. Off-host encrypted backups and a restore exercise are not
configured or proven. Same-disk backups do not protect against loss of the VPS.

The schema-generation **development** tool kysely-codegen still pulls braces 3.0.3
(GHSA-vfj7-8cjw-p6xm). The registry offers no patched braces version at review time.
This CLI is not part of the bundled runtime; deployment must exclude development
node_modules after building. Do not feed untrusted glob patterns to schema generation.
A blind downgrade to an incompatible generator is not a verified fix.

This audit does not prove absence of every vulnerability, resistance to volumetric
DDoS, physical-device security, production StoreKit behavior or 10,000-user capacity.
External Strix review was unavailable because its connection requires reauthentication;
no paid scan was started. Local inspection, dependency scans and regression checks ran.

Deployment: backend/admin panel/importer changes were installed in
`/srv/muwa/releases/security-20261006`; HTTPS health, anonymous admin rejection and
oversized-login rejection passed. Runtime node_modules were pruned to production
packages; npm audit there reports zero vulnerabilities. systemd hardening was verified
and activated; health stayed good. Private account/DB/config/state were preserved.

The first iOS CI run caught an error in my new fixture: its advertised oversized
response had no body, producing connection loss instead of exercising the size limit.
The fixture now sends actual oversized bytes with HTTP/1.1 for both known and unknown
length. Redirect and upload-cookie checks had already passed; a new run is required.
