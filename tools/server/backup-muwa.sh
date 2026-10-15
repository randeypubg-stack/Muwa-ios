#!/usr/bin/env bash
set -euo pipefail
umask 077
muwa_backup_root=/var/backups/muwa/daily
mkdir -p "$muwa_backup_root"
muwa_snapshot="$muwa_backup_root/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$muwa_snapshot"
trap 'rm -rf -- "$muwa_snapshot"' ERR
runuser -u postgres -- pg_dump --format=custom muwa > "$muwa_snapshot/database.dump"
# Uploaded objects are immutable. Hardlinks preserve deleted/replaced objects
# without duplicating the whole audio collection every day on the same NVMe.
cp -al /var/lib/muwa-app/media "$muwa_snapshot/media"
printf '%s\n' 'Local recovery copy; independent off-server backups are not configured.' > "$muwa_snapshot/README.txt"
find "$muwa_backup_root" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf -- {} +
printf '%s\n' 'Muwa local database/media backup completed.'
