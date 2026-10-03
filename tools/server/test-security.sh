#!/usr/bin/env bash
# Read-only helper checks and isolated UFW/Fail2ban configuration validation.
# Never enable a firewall, start a service or change the host configuration.
set -Eeuo pipefail
muwa_test_dir=$(mktemp -d)
trap 'rm -rf -- "$muwa_test_dir"' EXIT
muwa_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/server/secure-ubuntu.sh
source "$muwa_script_dir/secure-ubuntu.sh"
# Keep deliberate rejection checks quiet; main is never called here.
trap - ERR

for muwa_connection in '198.51.100.4 34567 203.0.113.5 22' '2001:db8::4 50000 2001:db8::5 2222'; do
    SSH_CONNECTION=$muwa_connection muwa_ssh_connection > "$muwa_test_dir/connection.json"
    python3 - "$muwa_test_dir/connection.json" "$muwa_connection" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    result = json.load(f)
client, _, server, port = sys.argv[2].split()
assert result == {"client": client, "server": server, "port": int(port)}
PY
done
for muwa_connection in '' 'bad 2 203.0.113.5 22' '198.51.100.4 0 203.0.113.5 22' \
    '198.51.100.4 34567 203.0.113.5 65536' '198.51.100.4 34567 203.0.113.5' \
    '198.51.100.4 34567 203.0.113.5 22 extra' 'fe80::1%eth0 123 2001:db8::5 22'; do
    if SSH_CONNECTION=$muwa_connection muwa_ssh_connection >/dev/null 2>&1; then
        printf 'Invalid SSH connection was accepted.\n' >&2
        exit 1
    fi
done
printf 'PASS: SSH port/client come from a validated IPv4 or IPv6 connection.\n'

cat > "$muwa_test_dir/sockets" <<'SOCKETS'
LISTEN 0 4096 127.0.0.53:53 0.0.0.0:*
LISTEN 0 128 [::1]:5432 [::]:*
LISTEN 0 128 0.0.0.0:2222 0.0.0.0:*
LISTEN 0 128 [::]:2222 [::]:*
LISTEN 0 128 *:443 *:*
LISTEN 0 128 203.0.113.5:80 0.0.0.0:*
SOCKETS
muwa_check_public_ports 2222 < "$muwa_test_dir/sockets"
for muwa_socket in 'LISTEN 0 128 0.0.0.0:5432 0.0.0.0:*' \
    'LISTEN 0 128 [::]:6379 [::]:*' 'LISTEN 0 128 *:3000 *:*' \
    'LISTEN 0 128 203.0.113.5:22 0.0.0.0:*' 'malformed' \
    'LISTEN 0 128 example.org:80 0.0.0.0:*'; do
    if printf '%s\n' "$muwa_socket" | muwa_check_public_ports 2222 >/dev/null 2>&1; then
        printf 'Unknown or malformed public socket was accepted.\n' >&2
        exit 1
    fi
done
printf 'PASS: public database/unknown ports stop setup; loopback services remain allowed.\n'

if [[ ${1:-} != --packages ]]; then
    [[ $# -eq 0 ]] || { printf 'Usage: test-security.sh [--packages]\n' >&2; exit 1; }
    exit 0
fi
[[ $# -eq 1 && $EUID -eq 0 ]] || { printf 'Package checks require an isolated root container.\n' >&2; exit 1; }
muwa_config_hashes() {
    find /etc/fail2ban /etc/ufw -type f -exec sha256sum {} + | sort
}
muwa_config_hashes > "$muwa_test_dir/config-before"
cp -a /etc/fail2ban "$muwa_test_dir/fail2ban"
for muwa_client in 198.51.100.4 2001:db8::4; do
    muwa_ssh_jail 2222 "$muwa_client" > "$muwa_test_dir/fail2ban/jail.d/muwa-ssh.local"
    fail2ban-client -c "$muwa_test_dir/fail2ban" -t
    fail2ban-client -c "$muwa_test_dir/fail2ban" -d > "$muwa_test_dir/fail2ban-dump"
    python3 - "$muwa_test_dir/fail2ban-dump" "$muwa_client" <<'PY'
import ast, sys
with open(sys.argv[1]) as f:
    commands = [ast.literal_eval(line) for line in f if line.startswith("[")]
assert ["add", "sshd", "systemd"] in commands
ignore = next(c for c in commands if c[:3] == ["set", "sshd", "addignoreip"])
assert sys.argv[2] in ignore[3:]
assert ["set", "sshd", "maxretry", 8] in commands
assert ["set", "sshd", "bantime", "15m"] in commands
assert ["set", "sshd", "findtime", "10m"] in commands
assert any(c[:3] == ["set", "sshd", "addaction"] and c[3] == "ufw" for c in commands)
PY
done
printf 'PASS: packaged Fail2ban validates journal, UFW action and owner IPv4/IPv6 exemption.\n'

# Verify real rule generation, including IPv6, without touching netfilter.
for muwa_port in 2222 80 443; do
    ufw --dry-run allow "$muwa_port/tcp" > "$muwa_test_dir/ufw-dry-run"
    python3 - "$muwa_test_dir/ufw-dry-run" "$muwa_port" <<'PY'
import sys
with open(sys.argv[1]) as f:
    rules = f.read()
for chain in ("ufw-user-input", "ufw6-user-input"):
    assert f"-A {chain} -p tcp --dport {sys.argv[2]} -j ACCEPT" in rules
PY
done
printf 'PASS: packaged UFW generates SSH/HTTP/HTTPS allow rules for both IP families.\n'
muwa_config_hashes > "$muwa_test_dir/config-after"
cmp -s "$muwa_test_dir/config-before" "$muwa_test_dir/config-after"
printf 'PASS: configuration validation changed no host UFW/Fail2ban files.\n'
