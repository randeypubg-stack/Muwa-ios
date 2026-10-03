# Muwa VPS preparation

The owner rented a server on 3 October 2026 and connected using Termius. The
screenshots identify Ubuntu 26.04.1 LTS, x86_64, 3.8 GiB RAM and a 38 GiB root
filesystem with approximately 35 GiB free. CPU count, provider and region have
not yet been verified. This is the owner's test host; capacity for 10,000 total
registered users still needs measurement and a separate media delivery plan.

`bootstrap-ubuntu.sh` prepares the host; it does **not** create a replacement
backend, empty account database, public media bucket, or a running Muwa service.
The existing Floot db/auth/storage adapters and data must first be exported and
adapted as described in [the migration plan](../../docs/CLOSED-BETA-HOSTING.md).

## Review and run

Download this file from an **immutable commit** on the existing Muwa repository,
verify the provided SHA-256, then execute it as root in the server's Termius
session. Do not run it in the local development environment or paste a collapsed
multiline script into the phone terminal. A downloaded script preserves newlines.

```bash
bash bootstrap-ubuntu.sh --check
bash bootstrap-ubuntu.sh
```

`--check` only reads host state. Installation requires Ubuntu 22.04, 24.04 or
26.04, amd64/arm64, a systemd VM, at least 2 GiB RAM and 4 GiB free disk. The
official Docker Ubuntu documentation and signed `resolute` release were checked
on 3 October 2026. The installer validates Docker's primary signing fingerprint.

The script installs Docker Engine/Compose v2, Python/venv, Git, jq and FFmpeg for
the prepared Telegram importer. A new Docker daemon receives rotated JSON logs
(10 MiB, three files per container). An existing healthy Docker/Compose install,
configuration and running containers remain unchanged. Conflicting runtimes are
reported rather than removed. No full system upgrade, reboot, SSH change or
Tailscale installation is performed.

If no swap is active, the script adds a 2 GiB file at `/var/lib/muwa/swapfile` and
its own fstab entry. Existing active swap is preserved. An unrecognized file at
that path causes a stop, never reformatting. A stopped run may be retried; existing
data and differing managed configurations are not overwritten. A process lock
prevents concurrent installation. An interrupted partial swap creation requires
manual review; do not blindly delete an existing swap file.

Installation output is saved in `/var/log/muwa-bootstrap.log`, root-readable
only, with a 2 MiB logrotate limit and three compressed generations. The final
`/var/lib/muwa/host-status.json` explicitly records
`muwa_deployed_by_this_script:false` and `database_migrated_by_this_script:false`.
These describe the installer, not a claim that any other existing deployment
has been removed. It contains no credentials. The final console output includes
listening TCP sockets for the subsequent firewall review.

## Next stage

Before deploying services, inspect listening sockets, the actual SSH port,
provider firewall and host rules. Then allow required web/SSH access without
breaking the owner's Termius session. Docker-published ports can bypass UFW;
publish only the intended HTTPS proxy, keep PostgreSQL/container administration
off public interfaces, and verify exposure from outside the VPS. This script
does not claim that a host firewall has been configured.

Preserve original account IDs/password hashes and track IDs, perform a staged
import with record counts/checksums, and keep the previous backend for rollback.
Use a private media origin, tested Range requests and owner beta access. Provide
off-host backups with a restoration check; `/var/backups/muwa` is only a local
staging directory. Do not activate paid ASR. Telegram export/history access still
needs the owner's channel confirmation and local credentials.

Validation before delivery: Bash syntax, ShellCheck and root/OS preflight checks.
The CI read-only check runs on Ubuntu 24.04. Package installation and swap on the
owner's actual Ubuntu 26.04 host remain unverified until its command output is
returned; do not report this script as already deployed.
