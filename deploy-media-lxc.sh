#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Proxmox LXC Media Stack Deployer
# Creates one Debian LXC and deploys a configurable media stack
# using Docker Compose.
#
# Run this on the Proxmox HOST, not inside a container.
#
# Project goal:
# - Easy test deployment for a home media automation stack
# - GitHub-friendly toggles so users can enable/disable apps
# - Readarr is intentionally not included because it is retired
#   upstream. LazyLibrarian, Kavita, and Audiobookshelf replace it.
# ============================================================

# ---------- PROXMOX / LXC SETTINGS ----------
CTID="120"
HOSTNAME="media-stack"

# Proxmox storage names
TEMPLATE_STORAGE="local"
ROOTFS_STORAGE="local-lvm"

# Container resources
# IMPORTANT:
# For pct create with local-lvm, use a plain number in GB.
# Example: local-lvm:64, not local-lvm:64G
DISK_SIZE="64"
MEMORY_MB="8192"
SWAP_MB="2048"
CORES="2"

# Network
BRIDGE="vmbr0"
IP_CONFIG="dhcp"

# Timezone
TZ="America/New_York"

# App user inside the LXC
APP_USER="media"
PUID="1000"
PGID="1000"

# Host paths to bind into the LXC
# Change these to match your actual storage paths on the Proxmox host.
HOST_MEDIA_PATH="/mnt/media"
HOST_DOWNLOADS_PATH="/mnt/downloads"

# Paths inside the LXC
LXC_MEDIA_PATH="/data/media"
LXC_DOWNLOADS_PATH="/data/downloads"

# App stack location inside the LXC
STACK_PATH="/opt/media-stack"

# Privileged LXC is easier for Docker-in-LXC.
# For stronger isolation, use a Debian VM instead.
UNPRIVILEGED="0"

# Log file on the Proxmox host
LOG_FILE="/root/deploy-media-lxc-${CTID}.log"
# ---------------------------------------------


# ---------- APP ENABLE/DISABLE TOGGLES ----------
# Set any of these to "0" to skip that app.
# They are all enabled by default for testing.

ENABLE_SONARR="1"
ENABLE_RADARR="1"
ENABLE_SABNZBD="1"
ENABLE_SEERR="1"
ENABLE_PROWLARR="1"
ENABLE_LIDARR="1"
ENABLE_BAZARR="1"

# Readarr replacement apps
ENABLE_LAZYLIBRARIAN="1"
ENABLE_KAVITA="1"
ENABLE_AUDIOBOOKSHELF="1"

# Optional torrent/VPN tools for later expansion.
# Disabled by default because VPN credentials and torrent settings vary.
ENABLE_QBITTORRENT="0"
ENABLE_GLUTUN="0"
ENABLE_AUTOBRR="0"
# -----------------------------------------------


# ---------- IMAGE SETTINGS ----------
IMAGE_SONARR="lscr.io/linuxserver/sonarr:latest"
IMAGE_RADARR="lscr.io/linuxserver/radarr:latest"
IMAGE_SABNZBD="lscr.io/linuxserver/sabnzbd:latest"
IMAGE_SEERR="ghcr.io/seerr-team/seerr:latest"
IMAGE_PROWLARR="lscr.io/linuxserver/prowlarr:latest"
IMAGE_LIDARR="lscr.io/linuxserver/lidarr:latest"
IMAGE_BAZARR="lscr.io/linuxserver/bazarr:latest"
IMAGE_LAZYLIBRARIAN="lscr.io/linuxserver/lazylibrarian:latest"
IMAGE_KAVITA="lscr.io/linuxserver/kavita:latest"
IMAGE_AUDIOBOOKSHELF="ghcr.io/advplyr/audiobookshelf:latest"

# Optional tools
IMAGE_QBITTORRENT="lscr.io/linuxserver/qbittorrent:latest"
IMAGE_GLUTUN="qmcgaw/gluetun:latest"
IMAGE_AUTOBRR="ghcr.io/autobrr/autobrr:latest"
# ------------------------------------


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
  URL_NOTES+=("${name}:http://\${LXC_IP}:${port}")
}

URL_NOTES=()

echo "============================================================"
echo "Proxmox Media LXC Deployment"
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
  echo "Edit TEMPLATE_STORAGE near the top of this script."
  exit 1
fi

if ! pvesm status | awk '{print $1}' | grep -qx "$ROOTFS_STORAGE"; then
  echo "Rootfs storage '$ROOTFS_STORAGE' was not found."
  echo "Edit ROOTFS_STORAGE near the top of this script."
  exit 1
fi

if pct status "$CTID" &>/dev/null; then
  echo "Container CTID $CTID already exists. Aborting."
  echo "If this is a failed previous attempt, run: pct destroy $CTID --purge"
  exit 1
fi

echo
echo "=== Preparing host bind-mount directories ==="
mkdir -p "$HOST_MEDIA_PATH" "$HOST_DOWNLOADS_PATH"

echo
echo "=== Updating Proxmox template list ==="
pveam update

TEMPLATE="$(pveam available --section system | awk '/debian-12-standard/ {print $2; exit}')"

if [[ -z "${TEMPLATE}" ]]; then
  echo "Could not find a Debian 12 standard template."
  echo "Available system templates:"
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
echo "=== Adding bind mounts ==="
pct set "$CTID" -mp0 "${HOST_MEDIA_PATH},mp=${LXC_MEDIA_PATH}"
pct set "$CTID" -mp1 "${HOST_DOWNLOADS_PATH},mp=${LXC_DOWNLOADS_PATH}"

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

mkdir -p ${STACK_PATH}/config
mkdir -p ${STACK_PATH}/metadata/audiobookshelf
mkdir -p ${LXC_MEDIA_PATH}/{movies,tv,music,books,ebooks,comics,manga,audiobooks,podcasts}
mkdir -p ${LXC_DOWNLOADS_PATH}/{complete,incomplete,torrents}

chown -R ${PUID}:${PGID} ${STACK_PATH}
chown -R ${PUID}:${PGID} ${LXC_MEDIA_PATH} ${LXC_DOWNLOADS_PATH} || true
"

echo
echo "=== Creating base Docker Compose file ==="
pct exec "$CTID" -- bash -lc "mkdir -p '${STACK_PATH}' && cat > '${STACK_PATH}/compose.yml'" <<EOF
services:
EOF

if is_enabled "$ENABLE_GLUTUN"; then
  add_service "gluetun" "  gluetun:
    image: ${IMAGE_GLUTUN}
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      - TZ=${TZ}
      # Configure these before enabling Gluetun:
      # - VPN_SERVICE_PROVIDER=custom
      # - VPN_TYPE=wireguard
      # - WIREGUARD_PRIVATE_KEY=
      # - WIREGUARD_ADDRESSES=
      # - SERVER_COUNTRIES=
    ports:
      - \"8081:8081\" # qBittorrent WebUI when qBittorrent uses network_mode: service:gluetun
      - \"6881:6881\"
      - \"6881:6881/udp\"
    restart: unless-stopped"
fi

if is_enabled "$ENABLE_SONARR"; then
  add_service "sonarr" "  sonarr:
    image: ${IMAGE_SONARR}
    container_name: sonarr
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_PATH}/config/sonarr:/config
      - ${LXC_MEDIA_PATH}:/data/media
      - ${LXC_DOWNLOADS_PATH}:/data/downloads
    ports:
      - \"8989:8989\"
    restart: unless-stopped"
  add_url_note "Sonarr" "8989"
fi

if is_enabled "$ENABLE_RADARR"; then
  add_service "radarr" "  radarr:
    image: ${IMAGE_RADARR}
    container_name: radarr
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_PATH}/config/radarr:/config
      - ${LXC_MEDIA_PATH}:/data/media
      - ${LXC_DOWNLOADS_PATH}:/data/downloads
    ports:
      - \"7878:7878\"
    restart: unless-stopped"
  add_url_note "Radarr" "7878"
fi

if is_enabled "$ENABLE_SABNZBD"; then
  add_service "sabnzbd" "  sabnzbd:
    image: ${IMAGE_SABNZBD}
    container_name: sabnzbd
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_PATH}/config/sabnzbd:/config
      - ${LXC_DOWNLOADS_PATH}/complete:/downloads
      - ${LXC_DOWNLOADS_PATH}/incomplete:/incomplete-downloads
    ports:
      - \"8080:8080\"
    restart: unless-stopped"
  add_url_note "SABnzbd" "8080"
fi

if is_enabled "$ENABLE_SEERR"; then
  add_service "seerr" "  seerr:
    image: ${IMAGE_SEERR}
    container_name: seerr
    init: true
    environment:
      - TZ=${TZ}
      - PORT=5055
    volumes:
      - ${STACK_PATH}/config/seerr:/app/config
    ports:
      - \"5055:5055\"
    restart: unless-stopped"
  add_url_note "Seerr" "5055"
fi

if is_enabled "$ENABLE_PROWLARR"; then
  add_service "prowlarr" "  prowlarr:
    image: ${IMAGE_PROWLARR}
    container_name: prowlarr
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_PATH}/config/prowlarr:/config
    ports:
      - \"9696:9696\"
    restart: unless-stopped"
  add_url_note "Prowlarr" "9696"
fi

if is_enabled "$ENABLE_LIDARR"; then
  add_service "lidarr" "  lidarr:
    image: ${IMAGE_LIDARR}
    container_name: lidarr
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_PATH}/config/lidarr:/config
      - ${LXC_MEDIA_PATH}:/data/media
      - ${LXC_DOWNLOADS_PATH}:/data/downloads
    ports:
      - \"8686:8686\"
    restart: unless-stopped"
  add_url_note "Lidarr" "8686"
fi

if is_enabled "$ENABLE_BAZARR"; then
  add_service "bazarr" "  bazarr:
    image: ${IMAGE_BAZARR}
    container_name: bazarr
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_PATH}/config/bazarr:/config
      - ${LXC_MEDIA_PATH}:/data/media
    ports:
      - \"6767:6767\"
    restart: unless-stopped"
  add_url_note "Bazarr" "6767"
fi

if is_enabled "$ENABLE_LAZYLIBRARIAN"; then
  add_service "lazylibrarian" "  lazylibrarian:
    image: ${IMAGE_LAZYLIBRARIAN}
    container_name: lazylibrarian
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_PATH}/config/lazylibrarian:/config
      - ${LXC_MEDIA_PATH}:/data/media
      - ${LXC_DOWNLOADS_PATH}:/data/downloads
    ports:
      - \"5299:5299\"
    restart: unless-stopped"
  add_url_note "LazyLibrarian" "5299"
fi

if is_enabled "$ENABLE_KAVITA"; then
  add_service "kavita" "  kavita:
    image: ${IMAGE_KAVITA}
    container_name: kavita
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${STACK_PATH}/config/kavita:/config
      - ${LXC_MEDIA_PATH}/books:/books
      - ${LXC_MEDIA_PATH}/comics:/comics
      - ${LXC_MEDIA_PATH}/manga:/manga
    ports:
      - \"5000:5000\"
    restart: unless-stopped"
  add_url_note "Kavita" "5000"
fi

if is_enabled "$ENABLE_AUDIOBOOKSHELF"; then
  add_service "audiobookshelf" "  audiobookshelf:
    image: ${IMAGE_AUDIOBOOKSHELF}
    container_name: audiobookshelf
    environment:
      - TZ=${TZ}
    volumes:
      - ${LXC_MEDIA_PATH}/audiobooks:/audiobooks
      - ${LXC_MEDIA_PATH}/podcasts:/podcasts
      - ${STACK_PATH}/config/audiobookshelf:/config
      - ${STACK_PATH}/metadata/audiobookshelf:/metadata
    ports:
      - \"13378:80\"
    restart: unless-stopped"
  add_url_note "Audiobookshelf" "13378"
fi

if is_enabled "$ENABLE_QBITTORRENT"; then
  if is_enabled "$ENABLE_GLUTUN"; then
    add_service "qbittorrent via gluetun" "  qbittorrent:
    image: ${IMAGE_QBITTORRENT}
    container_name: qbittorrent
    network_mode: \"service:gluetun\"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - WEBUI_PORT=8081
      - TORRENTING_PORT=6881
    volumes:
      - ${STACK_PATH}/config/qbittorrent:/config
      - ${LXC_DOWNLOADS_PATH}/torrents:/data/downloads/torrents
    depends_on:
      - gluetun
    restart: unless-stopped"
  else
    add_service "qbittorrent" "  qbittorrent:
    image: ${IMAGE_QBITTORRENT}
    container_name: qbittorrent
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - WEBUI_PORT=8081
      - TORRENTING_PORT=6881
    volumes:
      - ${STACK_PATH}/config/qbittorrent:/config
      - ${LXC_DOWNLOADS_PATH}/torrents:/data/downloads/torrents
    ports:
      - \"8081:8081\"
      - \"6881:6881\"
      - \"6881:6881/udp\"
    restart: unless-stopped"
  fi
  add_url_note "qBittorrent" "8081"
fi

if is_enabled "$ENABLE_AUTOBRR"; then
  add_service "autobrr" "  autobrr:
    image: ${IMAGE_AUTOBRR}
    container_name: autobrr
    environment:
      - TZ=${TZ}
    volumes:
      - ${STACK_PATH}/config/autobrr:/config
    ports:
      - \"7474:7474\"
    restart: unless-stopped"
  add_url_note "Autobrr" "7474"
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
echo "=== Starting media stack ==="
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
echo "Media stack deployed."
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
    # shellcheck disable=SC2016
    url="$(eval echo "$url_template")"
    printf "%-16s %s\n" "${name}:" "${url}"
  done
fi

echo
echo "Important paths inside apps:"
echo "Media:          ${LXC_MEDIA_PATH}"
echo "Downloads:      ${LXC_DOWNLOADS_PATH}"
echo "Movies:         ${LXC_MEDIA_PATH}/movies"
echo "TV:             ${LXC_MEDIA_PATH}/tv"
echo "Music:          ${LXC_MEDIA_PATH}/music"
echo "Books:          ${LXC_MEDIA_PATH}/books"
echo "Comics:         ${LXC_MEDIA_PATH}/comics"
echo "Manga:          ${LXC_MEDIA_PATH}/manga"
echo "Audiobooks:     ${LXC_MEDIA_PATH}/audiobooks"
echo "Podcasts:       ${LXC_MEDIA_PATH}/podcasts"
echo
echo "Stack path inside LXC:"
echo "${STACK_PATH}"
echo
echo "To view logs later:"
echo "cat ${LOG_FILE}"
echo "pct exec ${CTID} -- bash -lc 'cd ${STACK_PATH} && docker compose ps'"
echo "pct exec ${CTID} -- bash -lc 'cd ${STACK_PATH} && docker compose logs --tail=100'"
echo "============================================================"
