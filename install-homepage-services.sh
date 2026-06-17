#!/usr/bin/env bash
set -Eeuo pipefail

# Installs the bundled Homepage services.yaml into the monitoring LXC.
# Run this from the Proxmox host in the repo directory.

HOMEPAGE_CTID="${HOMEPAGE_CTID:-130}"
SOURCE_FILE="${SOURCE_FILE:-homepage-services.yaml}"
TARGET_FILE="/opt/monitoring-stack/config/homepage/services.yaml"

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "Could not find $SOURCE_FILE in the current directory."
  exit 1
fi

if ! pct status "$HOMEPAGE_CTID" &>/dev/null; then
  echo "Container $HOMEPAGE_CTID was not found."
  exit 1
fi

echo "Copying $SOURCE_FILE into CT $HOMEPAGE_CTID..."
pct push "$HOMEPAGE_CTID" "$SOURCE_FILE" "$TARGET_FILE"

echo "Fixing ownership..."
pct exec "$HOMEPAGE_CTID" -- bash -lc "chown 1000:1000 '$TARGET_FILE'"

echo "Restarting Homepage..."
pct exec "$HOMEPAGE_CTID" -- bash -lc 'cd /opt/monitoring-stack && docker compose restart homepage'

echo
echo "Homepage services installed."
echo "Open: http://$(pct exec "$HOMEPAGE_CTID" -- bash -lc "hostname -I | awk '{print \$1}'" | tr -d '\r'):3000"
