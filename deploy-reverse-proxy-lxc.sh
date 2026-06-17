#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Proxmox LXC Reverse Proxy Stack Deployer
# Creates one Debian LXC and deploys a configurable reverse proxy
# stack using Docker Compose.
#
# Run this on the Proxmox HOST, not inside a container.
# ============================================================

CTID="140"
HOSTNAME="reverse-proxy-stack"
TEMPLATE_STORAGE="local"
ROOTFS_STORAGE="local-lvm"
DISK_SIZE="16"
MEMORY_MB="2048"
SWAP_MB="1024"
CORES="1"
BRIDGE="vmbr0"
IP_CONFIG="dhcp"
TZ="America/New_York"
APP_USER="reverse-proxy"
PUID="1000"
PGID="1000"
STACK_PATH="/opt/reverse-proxy-stack"
UNPRIVILEGED="0"
LOG_FILE="/root/deploy-reverse-proxy-stack-${CTID}.log"

ENABLE_NGINX_PROXY_MANAGER="1"
ENABLE_CADDY="0"
ENABLE_CLOUDFLARED="0"
CLOUDFLARED_TOKEN="PASTE_TOKEN_HERE"

exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo; echo "ERROR: Script failed on line $LINENO."; echo "Log saved to: $LOG_FILE"; exit 1' ERR

is_enabled() { [[ "${1}" == "1" || "${1,,}" == "true" || "${1,,}" == "yes" ]]; }

add_service() {
  local service_name="$1"
  local content="$2"
  echo
  echo "Adding service: ${service_name}"
  pct exec "$CTID" -- bash -lc "cat >> '${STACK_PATH}/compose.yml'" <<< "$content"
}

add_url_note() {
  local name="$1"
  local port="$2"
  local scheme="${3:-http}"
  URL_NOTES+=("${name}:${scheme}://\${LXC_IP}:${port}")
}

URL_NOTES=()

echo "============================================================"
echo "Proxmox Reverse Proxy Stack Deployment"
echo "Started: $(date)"
echo "Log: $LOG_FILE"
echo "============================================================"
echo

command -v pct >/dev/null || { echo "pct not found. Run this on the Proxmox host."; exit 1; }
command -v pveam >/dev/null || { echo "pveam not found. Run this on the Proxmox host."; exit 1; }
command -v pvesm >/dev/null || { echo "pvesm not found. Run this on the Proxmox host."; exit 1; }

pvesm status

if ! pvesm status | awk '{print $1}' | grep -qx "$TEMPLATE_STORAGE"; then echo "Template storage '$TEMPLATE_STORAGE' was not found."; exit 1; fi
if ! pvesm status | awk '{print $1}' | grep -qx "$ROOTFS_STORAGE"; then echo "Rootfs storage '$ROOTFS_STORAGE' was not found."; exit 1; fi
if pct status "$CTID" &>/dev/null; then echo "Container CTID $CTID already exists. Run: pct destroy $CTID --purge"; exit 1; fi

pveam update
TEMPLATE="$(pveam available --section system | awk '/debian-12-standard/ {print $2; exit}')"
if [[ -z "${TEMPLATE}" ]]; then echo "Could not find a Debian 12 standard template."; exit 1; fi
if ! pveam list "$TEMPLATE_STORAGE" | awk '{print $1}' | grep -q "${TEMPLATE}"; then pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"; fi

pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY_MB" \
  --swap "$SWAP_MB" \
  --rootfs "${ROOTFS_STORAGE}:${DISK_SIZE}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CONFIG}" \
  --features "nesting=1,keyctl=1" \
  --unprivileged "$UNPRIVILEGED" \
  --onboot 1 \
  --ostype debian \
  --start 0

pct start "$CTID"

for i in {1..30}; do
  if pct exec "$CTID" -- bash -lc "ip route | grep -q default"; then echo "Container network is up."; break; fi
  if [[ "$i" -eq 30 ]]; then echo "Container did not get a default route."; exit 1; fi
  sleep 2
done

pct exec "$CTID" -- bash -lc "getent hosts deb.debian.org >/dev/null"
pct exec "$CTID" -- bash -lc "apt-get update"

pct exec "$CTID" -- bash -lc "
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y ca-certificates curl gnupg lsb-release sudo nano uidmap dbus locales
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
install -m 0755 -d /etc/apt/keyrings
rm -f /etc/apt/keyrings/docker.gpg
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --batch --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
if ! id ${APP_USER} >/dev/null 2>&1; then useradd -m -u ${PUID} -s /bin/bash ${APP_USER}; fi
usermod -aG docker ${APP_USER}
mkdir -p ${STACK_PATH}/config ${STACK_PATH}/data
chown -R ${PUID}:${PGID} ${STACK_PATH}
"

pct exec "$CTID" -- bash -lc "mkdir -p '${STACK_PATH}' && cat > '${STACK_PATH}/compose.yml'" <<EOF
services:
EOF

if is_enabled "$ENABLE_NGINX_PROXY_MANAGER"; then
  add_service "nginx-proxy-manager" "  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    environment:
      - TZ=${TZ}
      - DISABLE_IPV6=true
    volumes:
      - ${STACK_PATH}/config/nginx-proxy-manager/data:/data
      - ${STACK_PATH}/config/nginx-proxy-manager/letsencrypt:/etc/letsencrypt
    ports:
      - \"80:80\"
      - \"443:443\"
      - \"81:81\"
    restart: unless-stopped"
  add_url_note "Nginx Proxy Manager" "81"
fi

if is_enabled "$ENABLE_CADDY"; then
  pct exec "$CTID" -- bash -lc "mkdir -p '${STACK_PATH}/config/caddy' && touch '${STACK_PATH}/config/caddy/Caddyfile'"
  add_service "caddy" "  caddy:
    image: caddy:2
    container_name: caddy
    volumes:
      - ${STACK_PATH}/config/caddy/Caddyfile:/etc/caddy/Caddyfile
      - ${STACK_PATH}/config/caddy/data:/data
      - ${STACK_PATH}/config/caddy/config:/config
    ports:
      - \"80:80\"
      - \"443:443\"
      - \"443:443/udp\"
    restart: unless-stopped"
fi

if is_enabled "$ENABLE_CLOUDFLARED"; then
  if [[ "$CLOUDFLARED_TOKEN" == "PASTE_TOKEN_HERE" || -z "$CLOUDFLARED_TOKEN" ]]; then echo "Cloudflared is enabled but CLOUDFLARED_TOKEN is not set."; exit 1; fi
  add_service "cloudflared" "  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    command: tunnel --no-autoupdate run --token ${CLOUDFLARED_TOKEN}
    restart: unless-stopped"
fi

pct exec "$CTID" -- bash -lc "cat '${STACK_PATH}/compose.yml'"
pct exec "$CTID" -- bash -lc "cd '${STACK_PATH}' && docker compose config >/dev/null"
pct exec "$CTID" -- bash -lc "cd '${STACK_PATH}' && docker compose pull && docker compose up -d && docker compose ps"

LXC_IP="$(pct exec "$CTID" -- bash -lc "hostname -I | awk '{print \$1}'" | tr -d '\r')"

echo
echo "============================================================"
echo "Reverse Proxy stack deployed."
echo "LXC ID:       ${CTID}"
echo "Hostname:     ${HOSTNAME}"
echo "IP Address:   ${LXC_IP}"
echo "Enabled Web UIs:"
for item in "${URL_NOTES[@]}"; do name="${item%%:*}"; url_template="${item#*:}"; url="$(eval echo "$url_template")"; printf "%-22s %s\n" "${name}:" "${url}"; done
echo "Stack path inside LXC: ${STACK_PATH}"
echo "Log: ${LOG_FILE}"
echo "============================================================"
