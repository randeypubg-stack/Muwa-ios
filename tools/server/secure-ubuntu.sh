#!/usr/bin/env bash
# Configure the prepared Muwa firewall while preserving existing SSH protection.
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
    print(json.dumps({"client": client, "client_port": client_port, "server": server, "port": server_port}))
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

muwa_rollback_unit() {
    printf '%s\n' '# Managed by Muwa secure-ubuntu.sh' '[Unit]' \
        'Description=Revert an unconfirmed Muwa firewall change' 'StartLimitIntervalSec=0' '[Service]' \
        'Type=oneshot' 'ExecStart=/bin/bash /var/lib/muwa/security-rollback.sh --rollback %i' \
        'Restart=on-failure' 'RestartSec=5s'
}

muwa_rollback_timer() {
    printf '%s\n' '# Managed by Muwa secure-ubuntu.sh' '[Unit]' \
        'Description=Muwa firewall access confirmation deadline' '[Timer]' \
        'OnActiveSec=5min' 'AccuracySec=1s' 'Unit=muwa-security-rollback@%i.service' \
        '[Install]' 'WantedBy=timers.target'
}

muwa_guard_units() {
    local muwa_name muwa_function muwa_path
    for muwa_name in service timer; do
        muwa_path="/etc/systemd/system/muwa-security-rollback@.$muwa_name"
        muwa_function=muwa_rollback_unit
        [[ $muwa_name != timer ]] || muwa_function=muwa_rollback_timer
        [[ ! -L $muwa_path ]] || die 'Refusing a rollback unit symlink.'
        if [[ -e $muwa_path ]]; then
            [[ -f $muwa_path ]] || die 'Expected a regular rollback unit.'
            "$muwa_function" | cmp -s - "$muwa_path" || die 'An existing rollback unit differs; preserve it for review.'
        fi
    done
    [[ ! -L /var/lib/muwa/security-rollback.sh ]] || die 'Refusing a rollback script symlink.'
    if [[ -e /var/lib/muwa/security-rollback.sh ]]; then
        [[ -f /var/lib/muwa/security-rollback.sh ]] || die 'Expected a regular rollback script.'
        grep -qx '# Configure the prepared Muwa firewall while preserving existing SSH protection.' \
            /var/lib/muwa/security-rollback.sh || die 'An unknown rollback script requires review.'
    fi
}

muwa_read_pending() {
    local muwa_pending=/var/lib/muwa/security-pending.json
    [[ -f $muwa_pending && ! -L $muwa_pending ]] || die 'No pending Muwa firewall change.'
    jq -e '.token | type == "string" and test("^[a-f0-9]{32}$")' "$muwa_pending" >/dev/null ||
        die 'Invalid rollback token.'
    jq -r .token "$muwa_pending"
}

muwa_write_status() {
    local muwa_stage=$1 muwa_verified=$2 muwa_port=$3 muwa_status
    [[ ! -L /var/lib/muwa/security-status.json ]] || die 'Refusing a status file symlink.'
    muwa_status=$(mktemp /var/lib/muwa/.security-status.XXXXXXXX)
    jq -n --arg stage "$muwa_stage" --argjson ssh_port "$muwa_port" --argjson verified "$muwa_verified" \
        '{stage:$stage,ssh_port:$ssh_port,ufw_active:($stage != "host-security-reverted"),
          fail2ban_preserved:true,external_reconnect_verified:$verified,
          docker_published_ports_protected_by_ufw:false,application_deployed_by_this_script:false}' \
        > "$muwa_status"
    mv -fT "$muwa_status" /var/lib/muwa/security-status.json
}

muwa_rollback() {
    local muwa_expected=$1 muwa_token muwa_backup muwa_port
    [[ $muwa_expected =~ ^[a-f0-9]{32}$ ]] || die 'Invalid rollback token.'
    # An old timer must never revert a later change or an already confirmed one.
    [[ -e /var/lib/muwa/security-pending.json ]] || return 0
    muwa_token=$(muwa_read_pending)
    [[ $muwa_token == "$muwa_expected" ]] || return 0
    muwa_backup="/var/lib/muwa/security-change-$muwa_token"
    [[ -d $muwa_backup && ! -L $muwa_backup ]] || die 'Missing original firewall snapshot.'
    muwa_port=$(jq -r .connection.port /var/lib/muwa/security-pending.json)
    # Disable first to recover access even if restoring configuration fails.
    ufw --force disable
    cp -a "$muwa_backup/ufw/." /etc/ufw/
    cp -a "$muwa_backup/default-ufw" /etc/default/ufw
    systemctl disable --now "muwa-security-rollback@$muwa_token.timer"
    muwa_write_status host-security-reverted false "$muwa_port"
    rm -f /var/lib/muwa/security-pending.json
    printf 'MUWA: FIREWALL REVERTED. Existing Fail2ban and SSH settings were preserved.\n'
}

muwa_confirm_access() {
    local muwa_connection muwa_token muwa_pending=/var/lib/muwa/security-pending.json
    muwa_connection=$(muwa_ssh_connection) || exit 1
    muwa_token=$(muwa_read_pending)
    # Require a different authenticated TCP session to the same SSH endpoint.
    jq -e --argjson current "$muwa_connection" \
        '.connection != $current and .connection.server == $current.server and .connection.port == $current.port' \
        "$muwa_pending" >/dev/null || die 'Open a NEW Termius SSH connection before confirming access.'
    [[ $(LC_ALL=C ufw status | sed -n '1p') == 'Status: active' ]] || die 'Firewall is not active.'
    systemctl is-active --quiet fail2ban || die 'Existing Fail2ban is not active.'
    fail2ban-client status sshd >/dev/null || die 'Existing SSH protection is not active.'
    systemctl is-active --quiet "muwa-security-rollback@$muwa_token.timer" || die 'Rollback timer is no longer active.'
    muwa_write_status host-security-configured true "$(jq -r .port <<< "$muwa_connection")"
    rm -f "$muwa_pending"
    systemctl disable --now "muwa-security-rollback@$muwa_token.timer"
    printf 'MUWA: HOST SECURITY CONFIGURED. New SSH connection verified; rollback cancelled.\n'
    LC_ALL=C ufw status verbose
}

muwa_arm_rollback() {
    local muwa_connection=$1 muwa_token muwa_backup muwa_name muwa_function muwa_pending
    muwa_token=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
    muwa_backup="/var/lib/muwa/security-change-$muwa_token"
    install -d -m 700 "$muwa_backup/ufw"
    cp -a /etc/ufw/. "$muwa_backup/ufw/"
    cp -a /etc/default/ufw "$muwa_backup/default-ufw"
    install -m 700 "${BASH_SOURCE[0]}" /var/lib/muwa/security-rollback.sh
    for muwa_name in service timer; do
        muwa_function=muwa_rollback_unit
        [[ $muwa_name != timer ]] || muwa_function=muwa_rollback_timer
        "$muwa_function" > "$muwa_backup/unit"
        install -m 644 "$muwa_backup/unit" "/etc/systemd/system/muwa-security-rollback@.$muwa_name"
    done
    systemctl daemon-reload
    muwa_pending=$(mktemp /var/lib/muwa/.security-pending.XXXXXXXX)
    jq -n --arg token "$muwa_token" --argjson connection "$muwa_connection" \
        '{token:$token,connection:$connection}' > "$muwa_pending"
    mv -fT "$muwa_pending" /var/lib/muwa/security-pending.json
    if ! systemctl enable --now "muwa-security-rollback@$muwa_token.timer" ||
        ! systemctl is-active --quiet "muwa-security-rollback@$muwa_token.timer"; then
        rm -f /var/lib/muwa/security-pending.json
        systemctl disable --now "muwa-security-rollback@$muwa_token.timer" || true
        die 'Could not arm rollback; firewall not changed.'
    fi
    printf 'MUWA: ROLLBACK ARMED. Confirm a new SSH connection within five minutes.\n'
}

main() {
    local muwa_check=false muwa_connection muwa_port muwa_path
    case "${1:-}" in
        '') [[ $# -eq 0 ]] || die 'Invalid arguments.' ;;
        --check|--confirm-access) [[ $# -eq 1 ]] || die 'Invalid arguments.' ;;
        --rollback) [[ $# -eq 2 ]] || die 'Invalid arguments.' ;;
        *) die 'Usage: secure-ubuntu.sh [--check|--confirm-access]' ;;
    esac
    [[ $EUID -eq 0 ]] || die 'Run in the server console as root.'
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ ${ID:-} == ubuntu && ${VERSION_ID:-} =~ ^(22|24|26)\.04$ ]] || die 'Unverified operating system.'
    [[ -d /run/systemd/system ]] || die 'A systemd VM is required.'
    [[ -f /var/lib/muwa/host-status.json && ! -L /var/lib/muwa/host-status.json ]] ||
        die 'Complete Muwa host preparation first.'
    jq -e '.stage == "host-prepared"' /var/lib/muwa/host-status.json >/dev/null ||
        die 'Complete Muwa host preparation first.'
    if [[ ${1:-} != --check ]]; then
        exec 9>/run/muwa-bootstrap.lock
        flock -n 9 || die 'Another Muwa host setup is running; retry shortly.'
    else
        muwa_check=true
    fi
    case "${1:-}" in
        --rollback) muwa_rollback "$2"; return ;;
        --confirm-access) muwa_confirm_access; return ;;
    esac
    muwa_connection=$(muwa_ssh_connection) || exit 1
    muwa_port=$(jq -r .port <<< "$muwa_connection")
    ss -H -lnt | muwa_check_public_ports "$muwa_port" || exit 1
    for muwa_path in ufw fail2ban-client systemctl jq python3; do
        command -v "$muwa_path" >/dev/null || die "Required installed tool is missing: $muwa_path"
    done
    systemctl is-active --quiet fail2ban || die 'Existing Fail2ban must be active before changing the firewall.'
    fail2ban-client status sshd >/dev/null || die 'Existing SSH protection must be active.'
    [[ ! -e /var/lib/muwa/security-pending.json && ! -L /var/lib/muwa/security-pending.json ]] ||
        die 'A firewall change is pending. Confirm a new SSH connection or let it revert first.'
    [[ $(LC_ALL=C ufw status) == 'Status: inactive' ]] || die 'An active firewall requires separate review.'
    for muwa_path in /etc/ufw /etc/default/ufw /var/lib/muwa/security-status.json; do
        [[ ! -L $muwa_path ]] || die "Refusing a configuration symlink: $muwa_path"
    done
    if grep -qs '^### tuple ###' /etc/ufw/user.rules /etc/ufw/user6.rules; then
        die 'Existing custom firewall rules require review.'
    fi
    grep -q '^IPV6=yes' /etc/default/ufw || die 'IPv6 firewall is disabled; review the configuration.'
    grep -q '^MANAGE_BUILTINS=no' /etc/default/ufw || die 'UFW must preserve existing firewall chains.'
    muwa_guard_units
    printf 'MUWA: SSH port %s verified from the current connection; TCP policy is SSH/80/443.\n' "$muwa_port"
    if $muwa_check; then
        printf 'MUWA: SECURITY CHECK OK. No files or firewall rules changed.\n'
        return
    fi

    [[ ! -L /var/log/muwa-bootstrap.log ]] || die 'Refusing a log symlink.'
    exec > >(tee -a /var/log/muwa-bootstrap.log) 2>&1
    muwa_arm_rollback "$muwa_connection"
    # Add the port for this exact session before enabling restrictive defaults.
    ufw allow "$muwa_port/tcp" comment 'Muwa SSH'
    ufw allow 80/tcp comment 'Muwa HTTP certificate validation'
    ufw allow 443/tcp comment 'Muwa HTTPS'
    ufw default deny incoming
    ufw default allow outgoing
    ufw logging low
    ufw --force enable
    systemctl is-active --quiet fail2ban
    fail2ban-client status sshd
    [[ $(LC_ALL=C ufw status | sed -n '1p') == 'Status: active' ]] || die 'Firewall did not become active.'
    muwa_write_status host-security-awaiting-confirmation false "$muwa_port"
    printf '\nMUWA: FIREWALL PENDING. Within five minutes, open a NEW Termius connection and run:\n'
    printf 'bash /var/lib/muwa/security-rollback.sh --confirm-access\n'
    LC_ALL=C ufw status verbose
    printf 'MUWA: Docker services must bind only intended web ports; keep database ports private.\n'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
