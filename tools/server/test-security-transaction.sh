#!/usr/bin/env bash
# Execute the real installer in an isolated, non-systemd root container.
# UFW and service control are simulated; file snapshots/restoration are real.
set -Eeuo pipefail
[[ ${MUWA_ISOLATED_FIXTURE:-} == 1 && $EUID -eq 0 && $(cat /proc/1/comm) != systemd ]] || {
    printf 'This fixture requires an explicitly isolated root container.\n' >&2
    exit 1
}
muwa_test_dir=$(mktemp -d)
trap 'rm -rf -- "$muwa_test_dir"' EXIT
muwa_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export muwa_test_dir
install -d -m 700 /var/lib/muwa /run/systemd/system
printf '{"stage":"host-prepared"}\n' > /var/lib/muwa/host-status.json
printf '[sshd]\nenabled = true\nbackend = systemd\nbanaction = nftables-multiport\nmaxretry = 5\n' \
    > /etc/fail2ban/jail.d/provider.local
printf 'inactive\n' > "$muwa_test_dir/firewall"
export SSH_CONNECTION='198.51.100.4 34567 203.0.113.5 2222'

systemctl() {
    printf 'systemctl %s\n' "$*" >> "$muwa_test_dir/calls"
    case "$*" in
        'is-active --quiet fail2ban'|'daemon-reload') return 0 ;;
        'enable --now muwa-security-rollback@'*.timer)
            [[ ${MUWA_MOCK_ARM_FAIL:-0} != 1 ]] || return 1
            printf 'active\n' > "$muwa_test_dir/timer" ;;
        'is-active --quiet muwa-security-rollback@'*.timer)
            [[ $(cat "$muwa_test_dir/timer" 2>/dev/null) == active ]] ;;
        'disable --now muwa-security-rollback@'*.timer)
            printf 'inactive\n' > "$muwa_test_dir/timer" ;;
        *) printf 'Unexpected service mutation: %s\n' "$*" >&2; return 1 ;;
    esac
}
fail2ban-client() {
    printf 'fail2ban-client %s\n' "$*" >> "$muwa_test_dir/calls"
    [[ $* == 'status sshd' ]] || { printf 'Unexpected Fail2ban mutation.\n' >&2; return 1; }
    printf 'provider sshd protection remains active\n'
}
ss() {
    [[ $* == '-H -lnt' ]] || return 1
    printf 'LISTEN 0 128 0.0.0.0:2222 0.0.0.0:*\n'
}
ufw() {
    printf 'ufw %s\n' "$*" >> "$muwa_test_dir/calls"
    case "$*" in
        status|'status verbose') printf 'Status: %s\n' "$(cat "$muwa_test_dir/firewall")" ;;
        allow*)
            [[ ${MUWA_MOCK_ALLOW_FAIL:-0} != 1 ]] || return 1
            printf '# fixture: %s\n' "$*" >> /etc/ufw/user.rules ;;
        default*|'logging low') printf '# fixture: %s\n' "$*" >> /etc/default/ufw ;;
        '--force enable') printf 'active\n' > "$muwa_test_dir/firewall" ;;
        '--force disable') printf 'inactive\n' > "$muwa_test_dir/firewall" ;;
        *) printf 'Unexpected firewall operation.\n' >&2; return 1 ;;
    esac
}
export -f systemctl fail2ban-client ss ufw
run_setup() {
    bash -c 'source "$1"; shift; main "$@"' _ "$muwa_script_dir/secure-ubuntu.sh" "$@"
}
firewall_hashes() {
    find /etc/ufw -type f -exec sha256sum {} + | sort
    sha256sum /etc/default/ufw
}
firewall_hashes > "$muwa_test_dir/firewall-before"
find /etc/fail2ban -type f -exec sha256sum {} + | sort > "$muwa_test_dir/fail2ban-before"
run_setup --check
firewall_hashes > "$muwa_test_dir/firewall-after"
cmp "$muwa_test_dir/firewall-before" "$muwa_test_dir/firewall-after"
[[ ! -e /var/lib/muwa/security-pending.json ]]
printf 'PASS: preflight accepts the provider SSH jail without modifying its configuration.\n'

if MUWA_MOCK_ARM_FAIL=1 run_setup; then exit 1; fi
[[ $(cat "$muwa_test_dir/firewall") == inactive && ! -e /var/lib/muwa/security-pending.json ]]
firewall_hashes > "$muwa_test_dir/firewall-after"
cmp "$muwa_test_dir/firewall-before" "$muwa_test_dir/firewall-after"
printf 'PASS: failed rollback scheduling changes no firewall rules.\n'

run_setup
muwa_token=$(jq -r .token /var/lib/muwa/security-pending.json)
[[ $(cat "$muwa_test_dir/firewall") == active && $(cat "$muwa_test_dir/timer") == active ]]
[[ $(stat -c %a /var/lib/muwa/security-pending.json) == 600 ]]
[[ $(stat -c %a /var/lib/muwa/security-rollback.sh) == 700 ]]
systemd-analyze verify /etc/systemd/system/muwa-security-rollback@.service /etc/systemd/system/muwa-security-rollback@.timer
if run_setup --confirm-access; then exit 1; fi
if SSH_CONNECTION='198.51.100.4 34568 203.0.113.5 22' run_setup --confirm-access; then exit 1; fi
[[ $(cat "$muwa_test_dir/timer") == active && -f /var/lib/muwa/security-pending.json ]]
SSH_CONNECTION='198.51.100.4 34568 203.0.113.5 2222' run_setup --confirm-access
[[ $(cat "$muwa_test_dir/timer") == inactive && ! -e /var/lib/muwa/security-pending.json ]]
jq -e '.stage == "host-security-configured" and .external_reconnect_verified' /var/lib/muwa/security-status.json >/dev/null
run_setup --rollback "$muwa_token"
[[ $(cat "$muwa_test_dir/firewall") == active ]]
printf 'PASS: only a new SSH session to the same endpoint confirms access; a confirmed change cannot roll back.\n'

# Restore the fixture baseline; production rollback never runs after confirmation.
cp -a "/var/lib/muwa/security-change-$muwa_token/ufw/." /etc/ufw/
cp -a "/var/lib/muwa/security-change-$muwa_token/default-ufw" /etc/default/ufw
printf 'inactive\n' > "$muwa_test_dir/firewall"
run_setup
muwa_next_token=$(jq -r .token /var/lib/muwa/security-pending.json)
run_setup --rollback "$muwa_token"
[[ $(cat "$muwa_test_dir/firewall") == active && -f /var/lib/muwa/security-pending.json ]]
run_setup --rollback "$muwa_next_token"
[[ $(cat "$muwa_test_dir/firewall") == inactive && ! -e /var/lib/muwa/security-pending.json ]]
firewall_hashes > "$muwa_test_dir/firewall-after"
cmp "$muwa_test_dir/firewall-before" "$muwa_test_dir/firewall-after"
jq -e '.stage == "host-security-reverted" and (.external_reconnect_verified | not)' /var/lib/muwa/security-status.json >/dev/null
printf 'PASS: expired change restores original files; stale rollback cannot revert a newer generation.\n'

if MUWA_MOCK_ALLOW_FAIL=1 run_setup; then exit 1; fi
[[ -f /var/lib/muwa/security-pending.json && $(cat "$muwa_test_dir/timer") == active ]]
muwa_next_token=$(jq -r .token /var/lib/muwa/security-pending.json)
run_setup --rollback "$muwa_next_token"
firewall_hashes > "$muwa_test_dir/firewall-after"
cmp "$muwa_test_dir/firewall-before" "$muwa_test_dir/firewall-after"
printf 'PASS: a failed firewall command leaves rollback armed and the snapshot recoverable.\n'

find /etc/fail2ban -type f -exec sha256sum {} + | sort > "$muwa_test_dir/fail2ban-after"
cmp "$muwa_test_dir/fail2ban-before" "$muwa_test_dir/fail2ban-after"
if grep -E 'systemctl.*(stop|restart|reload).*fail2ban|fail2ban-client.*(reload|set)' "$muwa_test_dir/calls"; then exit 1; fi
printf 'PASS: provider Fail2ban configuration and service remain untouched in every scenario.\n'
