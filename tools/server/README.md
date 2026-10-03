# Muwa VPS preparation

The owner rented a server on 3 October 2026 and connected using Termius. The
screenshots identify Ubuntu 26.04.1 LTS, x86_64, 3.8 GiB RAM and a 38 GiB root
filesystem with approximately 33 GiB free after preparation. The final output
confirms 2 CPUs, Docker 29.8.2, Compose 5.6.0, 2 GiB active swap and HOST PREPARED.
Provider and region have not yet been verified. This is the owner's test host; capacity for 10,000 total
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

`secure-ubuntu.sh` is the next independent host-security stage. Run its pinned,
checksum-verified version inside the owner's authenticated Termius SSH session.
`--check` reads state without changing files/firewall rules. The script detects
the actual SSH port and current client IP from `SSH_CONNECTION`, validates both,
and refuses unknown public TCP services, existing unmanaged Fail2ban or firewall
rules. It allows the SSH port, 80/TCP and 443/TCP for IPv4/IPv6 before enabling
UFW with incoming-deny/outgoing-allow defaults. It does not change SSH keys,
root/password authentication or restart SSH.

Fail2ban uses the systemd journal, an explicitly installed Python systemd module,
the UFW action, eight failures per ten minutes and a fifteen-minute ban. The
current authenticated owner's IP is exempted to preserve access during setup.
Unknown or differing managed configurations cause a stop rather than an
overwrite. Partial runs with the matching Muwa jail can resume. If the owner's
IP changes on a subsequent run, the changed configuration needs review.
The completion marker is HOST SECURITY CONFIGURED, separate from HOST PREPARED.
Open a second Termius connection to check reconnecting before closing the first.
The status report explicitly leaves external reconnect verification false and
does not claim that UFW protects Docker-published ports.

Checks use valid/invalid IPv4/IPv6 SSH connections, unknown public database ports,
and loopback services. An isolated Ubuntu 26.04 fixture checks the actual packaged
Fail2ban parser and generates IPv4/IPv6 UFW rules in dry-run mode, comparing
configuration checksums before/after. These checks do not enable a firewall or
start services; the real VM completion output and external reconnect must still
be verified. Pending OS security updates also remain a separate host task.

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

The owner's 3 October 2026 output confirms Docker Engine 29.8.2 and Compose
5.6.0 installed successfully. The first installer stopped before swap creation:
`excl` was incorrectly supplied as an output flag to `dd`; the corrected code
uses `conv=excl`. The later owner screenshot confirms the complete host stage,
including swap. The app, database migration and host-security stage still require
their own verification; do not call Muwa deployed prematurely.

Validation: Bash syntax, ShellCheck, root/OS preflight, and real 4 MiB allocation
and formatting using GNU coreutils and Ubuntu 26 coreutils. The file tests also
verify preservation of files/symlinks/directories, a real write interruption via
`ulimit`, staging cleanup, and idempotent/conflicting/duplicate fstab handling.
They never activate swap or touch `/etc/fstab`. CI includes an isolated Ubuntu
26.04 container in addition to the Ubuntu 24.04 read-only host preflight.
