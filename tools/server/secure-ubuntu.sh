#!/usr/bin/env bash
# Configure the prepared Muwa host firewall and SSH brute-force protection.
# This does not deploy Muwa or migrate data; SSH authentication stays unchanged.
set -Eeuo pipefail
umask 077
trap 'printf "MUWA ERROR: security setup stopped at line %s (exit %s). Keep the current SSH session open.\n" "$LINENO" "$?" >&2' ERR

die() { printf 'MUWA ERROR: %s\n' "$*" >&2; exit 1; }

muwa_ssh_connection() {
    python3 -c '
import ipaddress, json, sys
try:
    fields = sys.argv[1].split()
    if len(fields) != 4 or "%" in fields[0] or "%" in fields[2]: raise ValueError()
    client = str(ipaddress.ip_address(fields[0]))
    server = str(ipaddress.ip_address(fields[2]))
    client_port, server_port = int(fields[1]), int(fields[3])
    if not (1 <= client_port <= 65535 and 1 <= server_port <= 65535): raise ValueError()
    print(json.dumps({"client": client, "server": server, "port": server_port}))
except ValueError:
    print("Run this script inside the authenticated Termius SSH session.", file=sys.stderr)
    sys.exit(1)
' "${SSH_CONNECTION:-}"
}

muwa_check_public_ports() {
    python3 -c '
import ipaddress, sys
try:
    allowed = {int(sys.argv[1]), 80, 443}
    if not 1 <= int(sys.argv[1]) <= 65535: raise ValueError()
    for line in sys.stdin:
        fields = line.split()
        if len(fields) < 5 or fields[0] != "LISTEN": raise ValueError()
        address, port = fields[3].rsplit(":", 1)
        address = address.strip("[]").split("%")[0]
        if not 1 <= int(port) <= 65535: raise ValueError()
        if address != "*" and ipaddress.ip_address(address).is_loopback: continue
        if int(port) not in allowed:
            sys.exit("Another public TCP service requires review before enabling the firewall.")
except ValueError:
    sys.exit("Unrecognized listening socket output or SSH port.")
' "$1"
}

muwa_ssh_jail() {
    local muwa_port=$1 muwa_client=$2
    printf '%s\n' '# Managed by Muwa secure-ubuntu.sh' '[sshd]' 'enabled = true' \
        'backend = systemd' "port = $muwa_port" 'banaction = ufw' \
        "ignoreip = 127.0.0.1/8 ::1 $muwa_client" 'usedns = no' \
        'findtime = 10m' 'bantime = 15m' 'maxretry = 8'
}

main() {
    local muwa_check=false muwa_connection muwa_port muwa_client muwa_jail muwa_pkg_state muwa_temp muwa_path muwa_attempt
    [[ $# -eq 0 || ( $# -eq 1 && $1 == --check ) ]] || die 'Usage: secure-ubuntu.sh [--check]'
    [[ $# -eq 0 ]] || muwa_check=true
    [[ $EUID -eq 0 ]] || die 'Run in the server console as root.'
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ ${ID:-} == ubuntu && ${VERSION_ID:-} =~ ^(22|24|26)\.04$ ]] || die 'Unverified operating system.'
    [[ -d /run/systemd/system ]] || die 'A systemd VM is required.'
    [[ -f /var/lib/muwa/host-status.json && ! -L /var/lib/muwa/host-status.json ]] ||
        die 'Complete Muwa host preparation first.'
    jq -e '.stage == "host-prepared"' /var/lib/muwa/host-status.json >/dev/null ||
        die 'Complete Muwa host preparation first.'
    muwa_connection=$(muwa_ssh_connection) || exit 1
    muwa_port=$(jq -r .port <<< "$muwa_connection")
    muwa_client=$(jq -r .client <<< "$muwa_connection")
    ss -H -lnt | muwa_check_public_ports "$muwa_port" || exit 1
    muwa_jail=/etc/fail2ban/jail.d/muwa-ssh.local
    for muwa_path in /etc/fail2ban /etc/fail2ban/jail.d "$muwa_jail"; do
        [[ ! -L $muwa_path ]] || die "Refusing a configuration symlink: $muwa_path"
    done
    for muwa_path in /etc/fail2ban /etc/fail2ban/jail.d; do
        [[ ! -e $muwa_path || -d $muwa_path ]] || die "Expected a configuration directory: $muwa_path"
    done
    [[ ! -e $muwa_jail || -f $muwa_jail ]] || die 'Expected a regular SSH protection configuration.'
    if [[ -e $muwa_jail ]]; then
        muwa_ssh_jail "$muwa_port" "$muwa_client" | cmp -s - "$muwa_jail" ||
            die 'SSH protection configuration differs; review it before changing it.'
    else
        muwa_pkg_state=$(dpkg-query -W -f='${db:Status-Status}' fail2ban 2>/dev/null || true)
        [[ $muwa_pkg_state != installed ]] || die 'An existing Fail2ban installation requires review.'
        if command -v ufw >/dev/null 2>&1; then
            [[ $(LC_ALL=C ufw status) == 'Status: inactive' ]] ||
                die 'An existing active firewall requires review.'
            if grep -qs '^### tuple ###' /etc/ufw/user.rules /etc/ufw/user6.rules; then
                die 'Existing custom firewall rules require review.'
            fi
        fi
    fi
    printf 'MUWA: SSH port %s verified from the current connection; TCP policy is SSH/80/443.\n' "$muwa_port"
    if $muwa_check; then
        printf 'MUWA: SECURITY CHECK OK. No files or firewall rules changed.\n'
        return
    fi

    exec 9>/run/muwa-bootstrap.lock
    flock -n 9 || die 'Another Muwa host setup is running.'
    [[ ! -L /var/log/muwa-bootstrap.log ]] || die 'Refusing a log symlink.'
    exec > >(tee -a /var/log/muwa-bootstrap.log) 2>&1
    muwa_temp=$(mktemp -d /run/muwa-security.XXXXXXXX)
    # main keeps this value for the EXIT handler after its local scope ends.
    muwa_security_temp=$muwa_temp
    trap 'rm -rf -- "$muwa_security_temp"' EXIT
    for muwa_path in /etc/fail2ban /etc/fail2ban/jail.d; do
        [[ -d $muwa_path ]] || install -d -m 755 "$muwa_path"
    done
    muwa_ssh_jail "$muwa_port" "$muwa_client" > "$muwa_temp/jail"
    if [[ ! -e $muwa_jail ]]; then
        install -m 644 "$muwa_temp/jail" "$muwa_jail"
    fi
    apt-get -o DPkg::Lock::Timeout=120 update
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get \
        -o DPkg::Lock::Timeout=120 -o Dpkg::Options::=--force-confold \
        install -y --no-install-recommends ufw fail2ban python3-systemd
    grep -q '^IPV6=yes' /etc/default/ufw || die 'IPv6 firewall is disabled; review the configuration.'
    fail2ban-client -t
    # Add the port for this exact session before enabling restrictive defaults.
    ufw allow "$muwa_port/tcp" comment 'Muwa SSH'
    ufw allow 80/tcp comment 'Muwa HTTP certificate validation'
    ufw allow 443/tcp comment 'Muwa HTTPS'
    ufw default deny incoming
    ufw default allow outgoing
    ufw logging low
    ufw --force enable
    systemctl enable --now fail2ban
    # systemctl can return before the Fail2ban control socket becomes available.
    for ((muwa_attempt=0; muwa_attempt<15; muwa_attempt++)); do
        if fail2ban-client ping >/dev/null 2>&1; then break; fi
        sleep 1
    done
    fail2ban-client ping
    fail2ban-client reload
    systemctl is-active --quiet fail2ban
    fail2ban-client status sshd
    [[ $(LC_ALL=C ufw status | sed -n '1p') == 'Status: active' ]] || die 'Firewall did not become active.'
    jq -n --argjson ssh_port "$muwa_port" \
        '{stage:"host-security-configured",ssh_port:$ssh_port,ufw_active:true,
          fail2ban_sshd_active:true,external_reconnect_verified:false,
          docker_published_ports_protected_by_ufw:false,application_deployed_by_this_script:false}' \
        > "$muwa_temp/status.json"
    [[ ! -L /var/lib/muwa/security-status.json ]] || die 'Refusing a status file symlink.'
    install -m 600 "$muwa_temp/status.json" /var/lib/muwa/security-status.json
    printf '\nMUWA: HOST SECURITY CONFIGURED. Open a second Termius connection to verify access.\n'
    LC_ALL=C ufw status verbose
    printf 'MUWA: Docker services must bind only intended web ports; keep database ports private.\n'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
