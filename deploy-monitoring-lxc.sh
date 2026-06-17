#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Proxmox LXC Monitoring Stack Deployer
# Creates one Debian LXC and deploys a configurable monitoring
# stack using Docker Compose.
#
# Run this on the Proxmox HOST, not inside a container.
# ============================================================

# ---------- PROXMOX / LXC SETTINGS ----------
CTID="130"
HOSTNAME="monitoring-stack"

TEMPLATE_STORAGE="local"
ROOTFS_STORAGE="local-lvm"

DISK_SIZE="32"
MEMORY_MB="4096"
SWAP_MB="1024"
CORES="2"

BRIDGE="vmbr0"
IP_CONFIG="dhcp"

TZ="America/New_York"

APP_USER="monitoring"
PUID="1000"
PGID="1000"

STACK_PATH="/opt/monitoring-stack"
UNPRIVILEGED="0"

LOG_FILE="/root/deploy-monitoring-stack-${CTID}.log"
# ---------------------------------------------


# ---------- APP ENABLE/DISABLE TOGGLES ----------
ENABLE_UPTIME_KUMA="1"
ENABLE_TAUTULLI="1"
ENABLE_HOMEPAGE="1"

# Scrutiny needs real disk/S.M.A.R.T. device access from the host.
# It is disabled by default because most generic LXCs will not have this wired in.
ENABLE_SCRUTINY="0"
# -----------------------------------------------


exec > >(tee -a "$LOG_FILE") 2>&1

trap 'echo; echo "ERROR: Script failed on line $LINENO."; echo "Log saved to: $LOG_FILE"; exit 1' ERR

is_enabled() {
  [[ "${1}" == "1" || "${1,,}" == "true" || "${1,,}" == "yes" ]]
}

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
echo "Proxmox Monitoring Stack Deployment"
echo "Started: $(date)"
echo "Log: $LOG_FILE"
echo "============================================================"
echo

echo "=== Checking Proxmox tools ==="
command -v pct >/dev/null || { echo "pct not found. Run this on the Proxmox host."; exit 1; }
command -v pveam >/dev/null || { echo "pveam not found. Run this on the Proxmox host."; exit 1; }
command -v pvesm >/dev/null || { echo "pvesm not found. Run this on the Proxmox host."; exit 1; }

echo
echo "=== Checking storage exists ==="
pvesm status

if ! pvesm status | awk '{print $1}' | grep -qx "$TEMPLATE_STORAGE"; then
  echo "Template storage '$TEMPLATE_STORAGE' was not found."
  exit 1
fi

if ! pvesm status | awk '{print $1}' | grep -qx "$ROOTFS_STORAGE"; then
  echo "Rootfs storage '$ROOTFS_STORAGE' was not found."
  exit 1
fi

if pct status "$CTID" &>/dev/null; then
  echo "Container CTID $CTID already exists. Aborting."
  echo "If this is a failed previous attempt, run: pct destroy $CTID --purge"
  exit 1
fi

echo
echo "=== Updating Proxmox template list ==="
pveam update

TEMPLATE="$(pveam available --section system | awk '/debian-12-standard/ {print $2; exit}')"

if [[ -z "${TEMPLATE}" ]]; then
  echo "Could not find a Debian 12 standard template."
  pveam available --section system
  exit 1
fi

echo "Selected template: ${TEMPLATE}"

if ! pveam list "$TEMPLATE_STORAGE" | awk '{print $1}' | grep -q "${TEMPLATE}"; then
  echo "=== Downloading template: ${TEMPLATE} ==="
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
else
  echo "=== Template already downloaded: ${TEMPLATE} ==="
fi

echo
echo "=== Creating LXC ${CTID} (${HOSTNAME}) ==="
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

echo
echo "=== Starting container ==="
pct start "$CTID"

echo
echo "=== Waiting for container network ==="
for i in {1..30}; do
  if pct exec "$CTID" -- bash -lc "ip route | grep -q default"; then
    echo "Container network is up."
    break
  fi

  if [[ "$i" -eq 30 ]]; then
    echo "Container did not get a default route."
    echo "Check DHCP, bridge ${BRIDGE}, and Proxmox networking."
    exit 1
  fi

  sleep 2
done

echo
echo "=== Testing internet and DNS from inside LXC ==="
pct exec "$CTID" -- bash -lc "getent hosts deb.debian.org >/dev/null"
pct exec "$CTID" -- bash -lc "apt-get update"

echo
echo "=== Installing Docker and Compose inside LXC ==="
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

echo \
  \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

docker version
docker compose version

if ! id ${APP_USER} >/dev/null 2>&1; then
  useradd -m -u ${PUID} -s /bin/bash ${APP_USER}
fi

usermod -aG docker ${APP_USER}

mkdir -p ${STACK_PATH}/config ${STACK_PATH}/data
chown -R ${PUID}:${PGID} ${STACK_PATH}
"

echo
echo "=== Creating base Docker Compose file ==="
pct exec "$CTID" -- bash -lc "mkdir -p '${STACK_PATH}' && cat > '${STACK_PATH}/compose.yml'" <<EOF
services:
EOF


if is_enabled "$ENABLE_UPTIME_KUMA"; then
  add_service "uptime-kuma" "  uptime-kuma:
    image: louislam/uptime-kuma:2
    container_name: uptime-kuma
    volumes:
      - ${STACK_PATH}/config/uptime-kuma:/app/data
    ports:
      - \"3001:3001\"
    restart: unless-stopped"
  add_url_note "Uptime Kuma" "3001"
fi

if is_enabled "$ENABLE_TAUTULLI"; then
  add_service "tautulli" "  tautulli:
    image: lscr.io/linuxserver/tautulli:latest
    container_name: tautulli
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_PATH}/config/tautulli:/config
    ports:
      - \"8181:8181\"
    restart: unless-stopped"
  add_url_note "Tautulli" "8181"
fi

if is_enabled "$ENABLE_HOMEPAGE"; then
  pct exec "$CTID" -- bash -lc "mkdir -p '${STACK_PATH}/config/homepage' && cat > '${STACK_PATH}/config/homepage/services.yaml'" <<EOF_SERVICES
---
- Monitoring:
    - Uptime Kuma:
        href: http://localhost:3001
        description: Uptime and service monitoring
    - Tautulli:
        href: http://localhost:8181
        description: Plex monitoring and analytics
EOF_SERVICES

  add_service "homepage" "  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - HOMEPAGE_ALLOWED_HOSTS=*
    volumes:
      - ${STACK_PATH}/config/homepage:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - \"3000:3000\"
    restart: unless-stopped"
  add_url_note "Homepage" "3000"
fi

if is_enabled "$ENABLE_SCRUTINY"; then
  add_service "scrutiny" "  scrutiny:
    image: ghcr.io/analogj/scrutiny:master-omnibus
    container_name: scrutiny
    cap_add:
      - SYS_RAWIO
    devices:
      # Add real disk devices here, for example:
      # - /dev/sda:/dev/sda
      # - /dev/sdb:/dev/sdb
    volumes:
      - ${STACK_PATH}/config/scrutiny:/opt/scrutiny/config
      - ${STACK_PATH}/data/scrutiny:/opt/scrutiny/influxdb
      - /run/udev:/run/udev:ro
    ports:
      - \"8082:8080\"
    restart: unless-stopped"
  add_url_note "Scrutiny" "8082"
fi


echo
echo "=== Generated Compose file ==="
pct exec "$CTID" -- bash -lc "cat '${STACK_PATH}/compose.yml'"

echo
echo "=== Validating Compose file ==="
pct exec "$CTID" -- bash -lc "
set -Eeuo pipefail
cd '${STACK_PATH}'
docker compose config >/dev/null
"

echo
echo "=== Starting stack ==="
pct exec "$CTID" -- bash -lc "
set -Eeuo pipefail
cd '${STACK_PATH}'

echo 'Pulling images...'
docker compose pull

echo 'Starting containers...'
docker compose up -d

echo 'Current container status:'
docker compose ps
"

LXC_IP="$(pct exec "$CTID" -- bash -lc "hostname -I | awk '{print \$1}'" | tr -d '\r')"

echo
echo "============================================================"
echo "Monitoring stack deployed."
echo
echo "LXC ID:       ${CTID}"
echo "Hostname:     ${HOSTNAME}"
echo "IP Address:   ${LXC_IP}"
echo "Specs:        ${CORES} cores, ${MEMORY_MB} MB RAM, ${DISK_SIZE} GB disk"
echo
echo "Enabled Web UIs:"

if [[ "${#URL_NOTES[@]}" -eq 0 ]]; then
  echo "No web apps were enabled."
else
  for item in "${URL_NOTES[@]}"; do
    name="${item%%:*}"
    url_template="${item#*:}"
    url="$(eval echo "$url_template")"
    printf "%-18s %s\n" "${name}:" "${url}"
  done
fi

echo
echo "Stack path inside LXC:"
echo "${STACK_PATH}"
echo
echo "To view logs later:"
echo "cat ${LOG_FILE}"
echo "pct exec ${CTID} -- bash -lc 'cd ${STACK_PATH} && docker compose ps'"
echo "pct exec ${CTID} -- bash -lc 'cd ${STACK_PATH} && docker compose logs --tail=100'"
echo "============================================================"
