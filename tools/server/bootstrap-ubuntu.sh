#!/usr/bin/env bash
# Muwa host preparation only. Does not deploy an app, database or media service.
set -Eeuo pipefail
umask 077

die() { printf 'MUWA ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '\nMUWA: %s\n' "$*"; }
trap 'printf "MUWA ERROR: stopped at line %s (exit %s). Fix the error before retrying.\n" "$LINENO" "$?" >&2' ERR

muwa_check_only=false
if [[ $# -gt 0 ]]; then
    [[ $# -eq 1 && $1 == --check ]] || die 'Usage: bootstrap-ubuntu.sh [--check]'
    muwa_check_only=true
fi
[[ $EUID -eq 0 ]] || die 'Run in the server console as root.'
[[ -r /etc/os-release ]] || die 'Cannot identify the operating system.'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || die 'Only Ubuntu is supported; no changes made.'
case "${VERSION_ID:-}" in
    22.04|24.04|26.04) ;;
    *) die "Unverified Ubuntu version: ${VERSION_ID:-unknown}; no changes made." ;;
esac
[[ -d /run/systemd/system ]] || die 'A systemd VM is required; no changes made.'
muwa_arch=$(dpkg --print-architecture)
case "$muwa_arch" in amd64|arm64) ;; *) die "Unsupported architecture: $muwa_arch" ;; esac
muwa_codename=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
case "$muwa_codename" in jammy|noble|resolute) ;; *) die 'Unverified Ubuntu codename.' ;; esac
muwa_ram_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
muwa_disk_kib=$(df -Pk / | awk 'NR == 2 {print $4}')
[[ $muwa_ram_kib -ge 2097152 ]] || die 'At least 2 GiB RAM is required.'
[[ $muwa_disk_kib -ge 4194304 ]] || die 'At least 4 GiB free disk space is required.'

docker_local() {
    env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS \
        -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
        docker --host=unix:///var/run/docker.sock "$@"
}
muwa_existing_docker=false
if command -v docker >/dev/null 2>&1; then
    docker_local version --format '{{.Server.Version}}' >/dev/null ||
        die 'An existing Docker installation is unhealthy. It will not be replaced.'
    docker_local compose version >/dev/null ||
        die 'Existing Docker lacks Compose v2. Review it before installing anything.'
    muwa_existing_docker=true
else
    for muwa_package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
        muwa_package_state=$(dpkg-query -W -f='${db:Status-Status}' "$muwa_package" 2>/dev/null || true)
        [[ $muwa_package_state != installed ]] ||
            die "Existing $muwa_package package requires review; it will not be removed."
    done
    if grep -qs 'download.docker.com/linux/ubuntu' /etc/apt/sources.list \
        /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; then
        # A prior partial run may own this single repository file.
        [[ -f /etc/apt/sources.list.d/muwa-docker.sources ]] ||
            die 'An existing Docker repository requires review.'
    fi
fi

for muwa_path in /opt/muwa /etc/muwa /var/lib/muwa /var/backups/muwa; do
    [[ ! -L $muwa_path ]] || die "Refusing symlink: $muwa_path"
    if [[ -e $muwa_path ]]; then
        [[ -d $muwa_path && $(stat -c %u "$muwa_path") == 0 ]] ||
            die "Existing path requires review: $muwa_path"
    fi
done
muwa_swap=/var/lib/muwa/swapfile
if [[ -e $muwa_swap || -L $muwa_swap ]]; then
    [[ -f $muwa_swap && ! -L $muwa_swap && $(stat -c %u "$muwa_swap") == 0 &&
        $(stat -c %a "$muwa_swap") == 600 &&
        $(blkid -p -s TYPE -o value "$muwa_swap" 2>/dev/null || true) == swap ]] ||
        die 'Existing Muwa swap file is unrecognized; it will not be reformatted.'
fi

say "Host: ${PRETTY_NAME:-Ubuntu}; $muwa_arch; $(nproc) CPU(s)."
free -h
df -h /
if $muwa_check_only; then
    say 'CHECK OK. No packages, files, services or firewall rules changed.'
    exit 0
fi

exec 9>/run/muwa-bootstrap.lock
flock -n 9 || die 'Another Muwa preparation is already running.'
[[ ! -L /var/log/muwa-bootstrap.log ]] || die 'Refusing a symlink for the installation log.'
touch /var/log/muwa-bootstrap.log
chmod 600 /var/log/muwa-bootstrap.log
exec > >(tee -a /var/log/muwa-bootstrap.log) 2>&1
muwa_temp_dir=$(mktemp -d /run/muwa-bootstrap.XXXXXXXX)
trap 'rm -rf -- "$muwa_temp_dir"' EXIT

apt_install() {
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get \
        -o DPkg::Lock::Timeout=120 -o Dpkg::Options::=--force-confold \
        install -y --no-install-recommends "$@"
}
say 'Installing tools from signed Ubuntu repositories.'
apt-get -o DPkg::Lock::Timeout=120 update
apt_install ca-certificates curl gnupg git jq python3 python3-venv ffmpeg logrotate

write_owned_file() {
    local muwa_target=$1 muwa_mode=$2 muwa_source=$3
    [[ ! -L $muwa_target ]] || die "Refusing symlink: $muwa_target"
    if [[ -e $muwa_target ]]; then
        cmp -s "$muwa_source" "$muwa_target" ||
            die "Existing configuration differs; review it before retrying: $muwa_target"
    else
        install -m "$muwa_mode" "$muwa_source" "$muwa_target"
    fi
}

if ! $muwa_existing_docker; then
    say 'Installing Docker Engine and Compose v2 from the official signed repository.'
    curl --fail --show-error --silent --location --retry 3 --connect-timeout 15 --max-time 90 \
        https://download.docker.com/linux/ubuntu/gpg -o "$muwa_temp_dir/docker.asc"
    install -d -m 700 "$muwa_temp_dir/gnupg"
    muwa_fingerprint=$(gpg --batch --homedir "$muwa_temp_dir/gnupg" --with-colons \
        --show-keys "$muwa_temp_dir/docker.asc" | awk -F: '$1 == "fpr" {print $10; exit}')
    [[ $muwa_fingerprint == 9DC858229FC7DD38854AE2D88D81803C0EBFCD88 ]] ||
        die 'Docker signing key fingerprint differs from the reviewed key.'
    install -d -m 755 /etc/apt/keyrings
    write_owned_file /etc/apt/keyrings/muwa-docker.asc 644 "$muwa_temp_dir/docker.asc"
    cat > "$muwa_temp_dir/docker.sources" <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $muwa_codename
Components: stable
Architectures: $muwa_arch
Signed-By: /etc/apt/keyrings/muwa-docker.asc
EOF
    write_owned_file /etc/apt/sources.list.d/muwa-docker.sources 644 "$muwa_temp_dir/docker.sources"
    install -d -m 755 /etc/docker
    [[ ! -L /etc/docker/daemon.json ]] || die 'Refusing a Docker config symlink.'
    if [[ ! -e /etc/docker/daemon.json ]]; then
        # Configure limits before the first daemon startup. Preserve any existing config.
        printf '%s\n' '{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}' \
            > "$muwa_temp_dir/daemon.json"
        write_owned_file /etc/docker/daemon.json 644 "$muwa_temp_dir/daemon.json"
    fi
    apt-get -o DPkg::Lock::Timeout=120 update
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
else
    say 'Preserving the existing Docker installation and its running containers.'
fi
docker_local version --format 'Docker Engine: {{.Server.Version}}'
docker_local compose version

for muwa_path in /opt/muwa /etc/muwa /var/lib/muwa /var/backups/muwa; do
    # Preserve permissions of existing directories and all existing data.
    [[ -d $muwa_path ]] || install -d -m 700 "$muwa_path"
done

if [[ $(swapon --show --noheadings | wc -l) -eq 0 ]]; then
    say 'Preparing 2 GiB swap for the 4 GiB test server.'
    if [[ ! -e $muwa_swap ]]; then
        dd if=/dev/zero of="$muwa_swap" bs=1M count=2048 oflag=excl status=none
        chmod 600 "$muwa_swap"
        mkswap "$muwa_swap"
    fi
    # Refuse to duplicate or override an existing fstab declaration.
    if awk -v path="$muwa_swap" '$1 == path {found=1} END {exit !found}' /etc/fstab; then
        awk -v path="$muwa_swap" '$1 == path && $2 == "none" && $3 == "swap" {ok=1} END {exit !ok}' \
            /etc/fstab || die 'Existing swap entry in fstab requires review.'
    else
        printf '\n%s none swap sw 0 0 # Muwa host preparation\n' "$muwa_swap" >> /etc/fstab
    fi
    swapon "$muwa_swap"
else
    say 'Preserving the existing active swap configuration.'
fi

cat > "$muwa_temp_dir/logrotate" <<'EOF'
/var/log/muwa-bootstrap.log {
    size 2M
    rotate 3
    compress
    missingok
    notifempty
    copytruncate
}
EOF
write_owned_file /etc/logrotate.d/muwa-bootstrap 644 "$muwa_temp_dir/logrotate"
jq -n --arg os "${PRETTY_NAME:-Ubuntu}" --arg arch "$muwa_arch" \
    --arg docker "$(docker_local version --format '{{.Server.Version}}')" \
    --argjson cpus "$(nproc)" \
    '{stage:"host-prepared",os:$os,architecture:$arch,cpus:$cpus,docker:$docker,
      muwa_deployed_by_this_script:false,database_migrated_by_this_script:false,
      firewall_configured_by_this_script:false}' \
    > "$muwa_temp_dir/status.json"
install -m 600 "$muwa_temp_dir/status.json" /var/lib/muwa/host-status.json
say 'HOST PREPARED. This script has not deployed Muwa or migrated a database.'
free -h
df -h /
say 'Listening TCP sockets for the next firewall review:'
ss -lntp
say 'Next: inspect firewall/listening ports, adapt and migrate the existing backend, then deploy.'
