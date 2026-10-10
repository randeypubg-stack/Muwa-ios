#!/usr/bin/env bash
set -euo pipefail
/opt/muwa/infra/certbot/bin/certbot renew --cert-name muwa-ip --quiet --no-random-sleep-on-renew --deploy-hook /opt/muwa/infra/reload-nginx.sh
