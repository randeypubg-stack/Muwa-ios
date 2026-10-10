# Muwa VPS preparation

The owner rented a server on 3 October 2026 and connected using Termius. The
screenshots identify Ubuntu 26.04.1 LTS, x86_64, 3.8 GiB RAM and a 38 GiB root
filesystem with approximately 33 GiB free after preparation. The final output
confirms 2 CPUs, Docker 29.8.2, Compose 5.6.0, 2 GiB active swap and HOST PREPARED.
The owner confirmed Beget as the provider and Russia as the region. This is the owner's test host; capacity for 10,000 total
registered users still needs measurement and a separate media delivery plan.

`bootstrap-ubuntu.sh` prepares the host; application deployment is a separate stage.
On 4 October the owner authorized a fresh Beget database and catalog, without
importing Floot records. That deployment is now running: PostgreSQL, the adapted
existing backend/admin panel, private NVMe media storage and trusted IP HTTPS.
See [current deployment and owner login](../../docs/BEGET-BETA-DEPLOYMENT.md).
The old Floot project remains untouched; an export or hosting top-up is not required.

## Confirmed remote access

Remote commands were verified on the expected Beget IPv4/hostname. Host settings
were saved under `/var/backups/muwa/pre-migration-20261004T093650Z/` before deployment.
Source snapshots preserve the existing implementation; snapshots do not restore
old database records. The current release is `/srv/muwa/current`.

The reviewed Desktop Commander 0.2.52 installation and npm lock were copied from
the working cache to `/opt/muwa/tools/desktop-commander`. The canonical service
is `/etc/systemd/system/muwa-remote-access.service`, matching the adjacent
[unit file](muwa-remote-access.service). It reuses the owner's existing device
registration; credential contents were not read or printed. The temporary
systemd service was replaced using an independent one-shot job, then the
persistent service and renewed remote execution were verified. Boot enablement
is configured; an actual reboot has not been tested. No SSH/firewall change or
reboot was performed. This unit assumes the verified installation exists; it
does not install or authorize a new agent.

`/var/lib/muwa/remote-access-status.json` and `migration-status.json` record the
observed stages privately on the VPS. The dated deployment document supersedes
earlier staging reports; native clients now target the Beget HTTPS origin.

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

The fresh-database scripts `init-fresh-beget.py`, `run-with-env.py`, service/proxy
units and certificate/backup scripts are the deployment sources for this beta.
The database initializer refuses an unrecognized existing database; it does not
reset a live deployment. Passwords and signing secrets are generated on the VPS
and stored privately. Do not commit generated env files or owner setup links.
Automatic ASR stays disabled. Telegram history import needs channel confirmation
and local credentials before actual ingestion; no channel has been copied yet.

The owner's 3 October 2026 output confirms Docker Engine 29.8.2 and Compose
5.6.0 installed successfully. The first installer stopped before swap creation:
`excl` was incorrectly supplied as an output flag to `dd`; the corrected code
uses `conv=excl`. The later owner screenshot confirms the complete host stage,
including swap. Host security is confirmed separately by the 4 October screenshot.
Application deployment is confirmed separately in the 4 October deployment report.

Validation: Bash syntax, ShellCheck, root/OS preflight, and real 4 MiB allocation
and formatting using GNU coreutils and Ubuntu 26 coreutils. The file tests also
verify preservation of files/symlinks/directories, a real write interruption via
`ulimit`, staging cleanup, and idempotent/conflicting/duplicate fstab handling.
They never activate swap or touch `/etc/fstab`. CI includes an isolated Ubuntu
26.04 container in addition to the Ubuntu 24.04 read-only host preflight.
