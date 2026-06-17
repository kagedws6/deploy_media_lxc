#!/usr/bin/env bash
set -Eeuo pipefail

# Adds optional static IP support to the deploy scripts in this repo.
# Run this from the repo directory after pulling the latest files.
#
# The script keeps DHCP as the default. To use static addressing in any
# deploy script, edit that deploy script and set USE_STATIC_IP="1".

python3 - <<'PY'
from pathlib import Path

configs = {
    "deploy-media-lxc.sh": "192.168.1.120/24",
    "deploy-monitoring-lxc.sh": "192.168.1.130/24",
    "deploy-reverse-proxy-lxc.sh": "192.168.1.140/24",
    "deploy-management-lxc.sh": "192.168.1.150/24",
    "deploy-security-lxc.sh": "192.168.1.160/24",
}

static_template = '''
# Optional static IP settings
# Leave USE_STATIC_IP="0" for DHCP. Set to "1" to use STATIC_IP.
USE_STATIC_IP="0"
STATIC_IP="{ip}"
GATEWAY="192.168.1.1"
DNS_SERVER="1.1.1.1"
SEARCH_DOMAIN="local"
'''

net_config_block = '''
if is_enabled "$USE_STATIC_IP"; then
  NET_IP_CONFIG="${STATIC_IP},gw=${GATEWAY}"
  echo "Using static IP: ${NET_IP_CONFIG}"
else
  NET_IP_CONFIG="${IP_CONFIG}"
  echo "Using IP config: ${NET_IP_CONFIG}"
fi

'''

dns_block = '''
if is_enabled "$USE_STATIC_IP"; then
  echo
  echo "=== Applying static DNS settings ==="
  pct set "$CTID" --nameserver "$DNS_SERVER" --searchdomain "$SEARCH_DOMAIN"
fi

'''

for filename, static_ip in configs.items():
    path = Path(filename)
    if not path.exists():
        print(f"Skipping missing file: {filename}")
        continue

    text = path.read_text()

    if "USE_STATIC_IP=" not in text:
        marker = 'IP_CONFIG="dhcp"\n'
        if marker not in text:
            raise SystemExit(f"Could not find IP_CONFIG marker in {filename}")
        text = text.replace(marker, marker + static_template.format(ip=static_ip), 1)

    if "NET_IP_CONFIG=" not in text:
        marker = 'echo\necho "=== Creating LXC'
        if marker in text:
            text = text.replace(marker, net_config_block + marker, 1)
        else:
            marker = 'pct create "$CTID"'
            if marker not in text:
                raise SystemExit(f"Could not find pct create marker in {filename}")
            text = text.replace(marker, net_config_block + marker, 1)

    text = text.replace('--net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CONFIG}"', '--net0 "name=eth0,bridge=${BRIDGE},ip=${NET_IP_CONFIG}"')

    if 'Applying static DNS settings' not in text:
        marker = 'echo\necho "=== Starting container ==="'
        if marker in text:
            text = text.replace(marker, dns_block + marker, 1)
        else:
            marker = 'pct start "$CTID"'
            if marker not in text:
                raise SystemExit(f"Could not find pct start marker in {filename}")
            text = text.replace(marker, dns_block + marker, 1)

    path.write_text(text)
    print(f"Updated {filename}")
PY

echo
echo "Static IP support has been applied to the deploy scripts."
echo "Review the settings near the top of each script before running."
