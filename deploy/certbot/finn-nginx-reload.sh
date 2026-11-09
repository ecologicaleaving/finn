#!/bin/sh
set -eu

# This shared Certbot hook directory also handles other domains on the VPS.
if [ "${RENEWED_LINEAGE:-}" != "/etc/letsencrypt/live/finn.8020solutions.org" ]; then
    exit 0
fi

nginx -t
systemctl reload nginx
