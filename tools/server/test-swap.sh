#!/usr/bin/env bash
# Real file/formatting checks; never enable swap or write the host's fstab.
set -Eeuo pipefail
muwa_test_dir=$(mktemp -d)
trap 'rm -rf -- "$muwa_test_dir"' EXIT
muwa_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/server/bootstrap-ubuntu.sh
source "$muwa_script_dir/bootstrap-ubuntu.sh"
assert_no_staging() {
    [[ -z $(find "$muwa_test_dir" -maxdepth 1 -type d -name '.muwa-swap.*' -print) ]]
}

muwa_create_swap_file "$muwa_test_dir/swapfile" 4
[[ $(stat -c %s "$muwa_test_dir/swapfile") -eq 4194304 ]]
[[ $(stat -c %a "$muwa_test_dir/swapfile") == 600 ]]
[[ $(blkid -p -s TYPE -o value "$muwa_test_dir/swapfile") == swap ]]
assert_no_staging
printf 'PASS: allocated and formatted a real 4 MiB swap file.\n'

muwa_swap_hash=$(sha256sum "$muwa_test_dir/swapfile")
if muwa_create_swap_file "$muwa_test_dir/swapfile" 4; then exit 1; fi
[[ $(sha256sum "$muwa_test_dir/swapfile") == "$muwa_swap_hash" ]]
printf 'PASS: existing swap data is preserved.\n'

printf 'owner data\n' > "$muwa_test_dir/owner-data"
muwa_data_hash=$(sha256sum "$muwa_test_dir/owner-data")
if muwa_create_swap_file "$muwa_test_dir/owner-data" 4; then exit 1; fi
ln -s "$muwa_test_dir/owner-data" "$muwa_test_dir/linked"
if muwa_create_swap_file "$muwa_test_dir/linked" 4; then exit 1; fi
[[ $(sha256sum "$muwa_test_dir/owner-data") == "$muwa_data_hash" ]]
mkdir "$muwa_test_dir/directory"
if muwa_create_swap_file "$muwa_test_dir/directory" 4; then exit 1; fi
[[ -d $muwa_test_dir/directory ]]
ln -s "$muwa_test_dir/missing" "$muwa_test_dir/dangling"
if muwa_create_swap_file "$muwa_test_dir/dangling" 4; then exit 1; fi
[[ -L $muwa_test_dir/dangling && ! -e $muwa_test_dir/missing ]]
assert_no_staging
printf 'PASS: ordinary files, symlinks and directories are preserved.\n'

for muwa_size in 0 -1 NaN 2G; do
    if muwa_create_swap_file "$muwa_test_dir/invalid" "$muwa_size"; then exit 1; fi
done
[[ ! -e $muwa_test_dir/invalid ]]
printf 'PASS: invalid allocation sizes cause no writes.\n'

# Exercise a genuine write failure using a process-local file size limit.
if (
    ulimit -c 0
    ulimit -f 1024
    muwa_create_swap_file "$muwa_test_dir/interrupted" 4
); then
    printf 'Expected the file size limit to interrupt allocation.\n' >&2
    exit 1
fi
[[ ! -e $muwa_test_dir/interrupted ]]
assert_no_staging
printf 'PASS: interrupted allocation publishes no partial swap file.\n'

printf '# fixture\nUUID=existing / ext4 defaults 0 1\n' > "$muwa_test_dir/fstab"
cp "$muwa_test_dir/fstab" "$muwa_test_dir/fstab-original"
muwa_ensure_swap_entry "$muwa_test_dir/fstab" /var/lib/muwa/swapfile
muwa_fstab_hash=$(sha256sum "$muwa_test_dir/fstab")
muwa_ensure_swap_entry "$muwa_test_dir/fstab" /var/lib/muwa/swapfile
[[ $(sha256sum "$muwa_test_dir/fstab") == "$muwa_fstab_hash" ]]
[[ $(awk '$1 == "/var/lib/muwa/swapfile" {n++} END {print n}' "$muwa_test_dir/fstab") == 1 ]]
head -n 2 "$muwa_test_dir/fstab" | cmp -s - "$muwa_test_dir/fstab-original"
printf 'PASS: fstab updates preserve other entries and are idempotent.\n'

printf '/var/lib/muwa/swapfile /data ext4 defaults 0 1\n' > "$muwa_test_dir/conflicting-fstab"
muwa_conflict_hash=$(sha256sum "$muwa_test_dir/conflicting-fstab")
if muwa_ensure_swap_entry "$muwa_test_dir/conflicting-fstab" /var/lib/muwa/swapfile; then exit 1; fi
[[ $(sha256sum "$muwa_test_dir/conflicting-fstab") == "$muwa_conflict_hash" ]]
cat "$muwa_test_dir/fstab" "$muwa_test_dir/fstab" > "$muwa_test_dir/duplicate-fstab"
muwa_duplicate_hash=$(sha256sum "$muwa_test_dir/duplicate-fstab")
if muwa_ensure_swap_entry "$muwa_test_dir/duplicate-fstab" /var/lib/muwa/swapfile; then exit 1; fi
[[ $(sha256sum "$muwa_test_dir/duplicate-fstab") == "$muwa_duplicate_hash" ]]
printf 'PASS: conflicting and duplicate fstab declarations are preserved for review.\n'
