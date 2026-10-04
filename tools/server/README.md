# Muwa VPS preparation

The owner rented a server on 3 October 2026 and connected using Termius. The
screenshots identify Ubuntu 26.04.1 LTS, x86_64, 3.8 GiB RAM and a 38 GiB root
filesystem with approximately 33 GiB free after preparation. The final output
confirms 2 CPUs, Docker 29.8.2, Compose 5.6.0, 2 GiB active swap and HOST PREPARED.
The owner confirmed Beget as the provider; region is not yet verified. This is the owner's test host; capacity for 10,000 total
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
bash bootstrap-ubuntu.sh --finish
```

`--check` only reads host state. Installation requires Ubuntu 22.04, 24.04 or
26.04, amd64/arm64, a systemd VM, at least 2 GiB RAM and 4 GiB free disk. The
official Docker Ubuntu documentation and signed `resolute` release were checked
on 3 October 2026. The installer validates Docker's primary signing fingerprint.

`--finish` resumes after package installation: it requires healthy Docker/Compose
and all prerequisite packages, then completes swap, log rotation and the host
report without running APT or restarting Docker.

The script installs Docker Engine/the Compose plugin, Python/venv, Git, jq and FFmpeg for
the prepared Telegram importer. A new Docker daemon receives rotated JSON logs
(10 MiB, three files per container). An existing healthy Docker/Compose install,
configuration and running containers remain unchanged. Conflicting runtimes are
reported rather than removed. No full system upgrade, reboot, SSH change or
Tailscale installation is performed.

If no swap is active, the script prepares a 2 GiB file in a private temporary
directory on the same filesystem, formats it, and publishes it with an exclusive
hard link at `/var/lib/muwa/swapfile`. A failed allocation cannot publish a
partial file at that path. Existing swap files, symlinks and directories are not
replaced. Normal write/format/publish failures remove the temporary staging
directory. SIGKILL/power loss can leave hidden staging directories requiring
manual review. A valid but inactive swap file is reused; an unrecognized managed
path causes a stop, never reformatting. The fstab entry is added once; conflicting
or duplicate declarations are preserved for review. A process lock prevents
concurrent installation. Existing active swap is preserved.

Installation output is saved in `/var/log/muwa-bootstrap.log`, root-readable
only, with a 2 MiB logrotate limit and three compressed generations. The final
`/var/lib/muwa/host-status.json` explicitly records
`muwa_deployed_by_this_script:false` and `database_migrated_by_this_script:false`.
These describe the installer, not a claim that any other existing deployment
has been removed. It contains no credentials. The final console output includes
listening TCP sockets for the subsequent firewall review.

## Next stage

`secure-ubuntu.sh` handles the independent host-security stage. Before this stage,
the owner's screenshot confirmed that Beget already installed an active Fail2ban
SSH jail, with systemd journal matching, while UFW was inactive. The previous script
stopped at its pre-existing-Fail2ban guard before mutations. The temporary SSH
timeout remains unexplained; it is not evidence that that run enabled UFW.

The updated script requires installed UFW and an active existing Fail2ban SSH
jail. It performs no package installation, changes no Fail2ban configuration,
does not reload/restart its service, and preserves SSH authentication. It reads
the real client/server IPs and ports from the authenticated SSH connection.
Unknown public TCP services, custom UFW rules, an already active UFW, unknown
rollback units or a pending change cause a stop for inspection. UFW must handle
IPv6 and preserve other built-in firewall chains (`MANAGE_BUILTINS=no`).

Run the pinned, checksum-verified script in Termius. `--check` is read-only.
Before changing UFW, it snapshots configuration to a private root-owned directory
and enables a systemd rollback timer. If scheduling fails, no firewall rules are
changed. The timer runs independently of the SSH shell and remains enabled over
a reboot, with a new five-minute window when activated after boot. Failed
rollback jobs retry. Generation tokens and the host setup lock prevent old jobs
from reverting a newer or already confirmed change.

The script then allows the actual SSH port, 80/TCP and 443/TCP for IPv4/IPv6 and
enables incoming-deny/outgoing-allow defaults. FIREWALL PENDING means the change
still requires a **new authenticated SSH connection to the same endpoint**.
Within five minutes, open another Termius connection and run:

```bash
bash /var/lib/muwa/security-rollback.sh --confirm-access
```

The original TCP connection cannot confirm its own accessibility. After a valid
new connection, HOST SECURITY CONFIGURED records external reconnect verification
and cancels the timer. Without confirmation, the timer disables UFW and restores
its original files, while preserving Fail2ban configuration/service and SSH
settings. Snapshots remain available for review. Docker-published ports are
explicitly not claimed to be protected by UFW.

The owner's 4 October 2026 screenshot confirms HOST SECURITY CONFIGURED on the
VPS: UFW is active, incoming/routed traffic is denied by default, outgoing traffic
is allowed, and TCP 22/80/443 are allowed for IPv4/IPv6. Confirmation ran in a new
authenticated SSH connection and removed the rollback timer. The existing
provider Fail2ban configuration/service was preserved. No Muwa application or
database has been deployed by these preparation/security scripts.

Checks use IPv4/IPv6 SSH connections, unknown public database ports and loopback
services. An isolated Ubuntu 26.04 fixture validates the actual UFW dry-run rules,
Fail2ban parser and systemd unit syntax. Transaction scenarios run the real
installer with simulated firewall/service control and real file snapshots:
failed scheduling, original/wrong/new SSH sessions, expiry, stale generation,
failed firewall mutation and preservation of provider config. CI does not run a
live systemd timer or change kernel firewall rules. Enabling UFW on the VPS and
successful SSH reconnection are confirmed by the owner's output; timer expiry on
the real VM has not been observed. Pending OS security updates remain a separate task.

Before deploying services, inspect listening sockets, the actual SSH port,
provider firewall and host rules. Then allow required web/SSH access without
breaking the owner's Termius session. Docker-published ports can bypass UFW;
publish only the intended HTTPS proxy, keep PostgreSQL/container administration
off public interfaces, and verify exposure from outside the VPS. Host preparation
alone does not configure a firewall; security setup has its own completion report.

Preserve original account IDs/password hashes and track IDs, perform a staged
import with record counts/checksums, and keep the previous backend for rollback.
Use a private media origin, tested Range requests and owner beta access. Provide
off-host backups with a restoration check; `/var/backups/muwa` is only a local
staging directory. Do not activate paid ASR. Telegram export/history access still
needs the owner's channel confirmation and local credentials.

Source access is a prerequisite for migration. Floot's 4 October 2026 account
status reports exhausted hosting credit: the published app is offline and
PostgreSQL connections are disabled, with all data preserved. Source files remain
readable, but a source/schema-type snapshot is not a database backup. A verified
existing backup/export or restored database access is needed before transferring
accounts/catalog records. No hosting credit was purchased. See the
[migration status](../../docs/CLOSED-BETA-HOSTING.md) and
[Floot hosting balance](https://floot.com/dashboard/hosting).

The owner's 3 October 2026 output confirms Docker Engine 29.8.2 and Compose
5.6.0 installed successfully. The first installer stopped before swap creation:
`excl` was incorrectly supplied as an output flag to `dd`; the corrected code
uses `conv=excl`. The later owner screenshot confirms the complete host stage,
including swap. Host security is confirmed separately by the 4 October screenshot.
The app and database migration still require their own verification; do not call
Muwa deployed prematurely.

Validation: Bash syntax, ShellCheck, root/OS preflight, and real 4 MiB allocation
and formatting using GNU coreutils and Ubuntu 26 coreutils. The file tests also
verify preservation of files/symlinks/directories, a real write interruption via
`ulimit`, staging cleanup, and idempotent/conflicting/duplicate fstab handling.
They never activate swap or touch `/etc/fstab`. CI includes an isolated Ubuntu
26.04 container in addition to the Ubuntu 24.04 read-only host preflight.
