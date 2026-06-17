# deploy_media_lxc

Configurable Proxmox LXC deployment scripts for spinning up a self-hosted homelab media and utility stack with Docker Compose.

## Available scripts

| Script | Default CTID | Purpose | Enabled by default |
|---|---:|---|---|
| `deploy-media-lxc.sh` | 120 | Media automation | Sonarr, Radarr, SABnzbd, Seerr, Prowlarr, Lidarr, Bazarr, LazyLibrarian, Kavita, Audiobookshelf |
| `deploy-monitoring-lxc.sh` | 130 | Monitoring and dashboards | Uptime Kuma, Tautulli, Homepage |
| `deploy-reverse-proxy-lxc.sh` | 140 | Reverse proxy / ingress | Nginx Proxy Manager |
| `deploy-management-lxc.sh` | 150 | Docker management and logs | Portainer, Dozzle |
| `deploy-security-lxc.sh` | 160 | DNS blocking and password vault | AdGuard Home, Vaultwarden |
| `apply-static-ip-support.sh` | n/a | Helper that patches the deploy scripts to add optional static IP settings | n/a |
| `homepage-services.yaml` | n/a | Ready-to-use Homepage dashboard services file for the generated stack | n/a |
| `install-homepage-services.sh` | n/a | Copies `homepage-services.yaml` into CT 130 and restarts Homepage | n/a |

Some apps are included but disabled by default because they require extra secrets, port planning, or device passthrough:

- qBittorrent, Gluetun, and Autobrr in the media script
- Scrutiny in the monitoring script
- Caddy and Cloudflared in the reverse proxy script
- Watchtower in the management script
- Pi-hole in the security script

> These scripts are intended for homelab use. Review each script before running it, especially storage paths, LXC IDs, privileged container settings, static IP settings, and VPN-related options.

## Quick download from Proxmox

Run these from the Proxmox host shell:

```bash
curl -fsSL -O https://raw.githubusercontent.com/kagedws6/deploy_media_lxc/main/deploy-media-lxc.sh
curl -fsSL -O https://raw.githubusercontent.com/kagedws6/deploy_media_lxc/main/deploy-monitoring-lxc.sh
curl -fsSL -O https://raw.githubusercontent.com/kagedws6/deploy_media_lxc/main/deploy-reverse-proxy-lxc.sh
curl -fsSL -O https://raw.githubusercontent.com/kagedws6/deploy_media_lxc/main/deploy-management-lxc.sh
curl -fsSL -O https://raw.githubusercontent.com/kagedws6/deploy_media_lxc/main/deploy-security-lxc.sh
chmod +x deploy-*.sh
```

Or clone the repo:

```bash
apt update
apt install -y git
git clone https://github.com/kagedws6/deploy_media_lxc.git
cd deploy_media_lxc
chmod +x *.sh
```

## Basic use

1. Download or clone the repo on the Proxmox host.
2. Edit the script you want to run.
3. Review `CTID`, storage names, disk size, bridge, timezone, app toggles, and paths.
4. Make it executable with `chmod +x script-name.sh`.
5. Run it from the Proxmox host shell.

Example:

```bash
nano deploy-media-lxc.sh
chmod +x deploy-media-lxc.sh
./deploy-media-lxc.sh
```

## Common settings to review

```bash
CTID="120"
HOSTNAME="media-stack"
TEMPLATE_STORAGE="local"
ROOTFS_STORAGE="local-lvm"
DISK_SIZE="64"
MEMORY_MB="8192"
SWAP_MB="2048"
CORES="2"
BRIDGE="vmbr0"
IP_CONFIG="dhcp"
TZ="America/New_York"
```

Media script storage paths:

```bash
HOST_MEDIA_PATH="/mnt/media"
HOST_DOWNLOADS_PATH="/mnt/downloads"
```

Important notes:

- `CTID` must be unused.
- `ROOTFS_STORAGE` should match your Proxmox storage name, commonly `local-lvm`.
- `DISK_SIZE` should be a plain number, such as `64`, not `64G`.
- `HOST_MEDIA_PATH` and `HOST_DOWNLOADS_PATH` should point to storage paths on the Proxmox host.

Check Proxmox storage names with:

```bash
pvesm status
```

## Optional static IP support

The repo includes `apply-static-ip-support.sh`, which patches all deploy scripts so they can use either DHCP or static IPs.

Run this from the repo directory:

```bash
chmod +x apply-static-ip-support.sh
./apply-static-ip-support.sh
```

After running it, each deploy script gets a section like this near the top:

```bash
# Optional static IP settings
# Leave USE_STATIC_IP="0" for DHCP. Set to "1" to use STATIC_IP.
USE_STATIC_IP="0"
STATIC_IP="192.168.1.120/24"
GATEWAY="192.168.1.1"
DNS_SERVER="1.1.1.1"
SEARCH_DOMAIN="local"
```

To use static IPs, change `USE_STATIC_IP="0"` to `USE_STATIC_IP="1"` and adjust the address before running the deploy script.

Default static IP suggestions:

| Stack | Suggested static IP |
|---|---|
| Media | `192.168.1.120/24` |
| Monitoring | `192.168.1.130/24` |
| Reverse proxy | `192.168.1.140/24` |
| Management | `192.168.1.150/24` |
| Security | `192.168.1.160/24` |

Do not use an address that is already assigned on your network.

## Enable or disable apps

Each script has app toggles near the top.

Use `1` to enable an app and `0` to disable it:

```bash
ENABLE_SONARR="1"
ENABLE_RADARR="1"
ENABLE_SABNZBD="1"
ENABLE_SEERR="1"
ENABLE_GLUTUN="0"
ENABLE_CLOUDFLARED="0"
ENABLE_WATCHTOWER="0"
ENABLE_SCRUTINY="0"
```

> Gluetun requires VPN-specific configuration before it should be enabled. Cloudflared requires a tunnel token. Scrutiny requires host disk/S.M.A.R.T. device passthrough. Watchtower can auto-update containers, so enable it carefully.

## Homepage dashboard setup

The repo includes a ready-made Homepage services file based on this stack:

```text
homepage-services.yaml
```

To install it into the monitoring stack, run this from the repo directory on the Proxmox host:

```bash
chmod +x install-homepage-services.sh
./install-homepage-services.sh
```

By default, this copies `homepage-services.yaml` into CT `130` at:

```text
/opt/monitoring-stack/config/homepage/services.yaml
```

Then it restarts the Homepage container.

Open Homepage at:

```text
http://MONITORING-LXC-IP:3000
```

For Patrick's current test deployment, the dashboard entries use these addresses:

| Stack | IP |
|---|---|
| Media | `192.168.1.254` |
| Monitoring | `192.168.1.184` |
| Reverse proxy | `192.168.1.225` |
| Management | `192.168.1.208` |
| Security | `192.168.1.245` |
| Proxmox host | `192.168.1.102` |

If your IPs differ, edit `homepage-services.yaml` before installing it.

## Default web ports

### Media stack

| App | Port |
|---|---:|
| Sonarr | 8989 |
| Radarr | 7878 |
| SABnzbd | 8080 |
| Seerr | 5055 |
| Prowlarr | 9696 |
| Lidarr | 8686 |
| Bazarr | 6767 |
| LazyLibrarian | 5299 |
| Kavita | 5000 |
| Audiobookshelf | 13378 |
| qBittorrent, optional | 8081 |
| Autobrr, optional | 7474 |

### Utility stacks

| Stack | App | Port |
|---|---|---:|
| Monitoring | Uptime Kuma | 3001 |
| Monitoring | Tautulli | 8181 |
| Monitoring | Homepage | 3000 |
| Monitoring | Scrutiny, optional | 8082 |
| Reverse Proxy | Nginx Proxy Manager | 81 |
| Reverse Proxy | HTTP | 80 |
| Reverse Proxy | HTTPS | 443 |
| Management | Portainer | 9443 |
| Management | Dozzle | 8088 |
| Security | AdGuard Home setup | 3000 |
| Security | AdGuard Home DNS | 53 |
| Security | Vaultwarden | 11001 |
| Security | Pi-hole, optional | 8084 |

## Container status checks

```bash
pct list

pct exec 120 -- bash -lc 'cd /opt/media-stack && docker compose ps'
pct exec 130 -- bash -lc 'cd /opt/monitoring-stack && docker compose ps'
pct exec 140 -- bash -lc 'cd /opt/reverse-proxy-stack && docker compose ps'
pct exec 150 -- bash -lc 'cd /opt/management-stack && docker compose ps'
pct exec 160 -- bash -lc 'cd /opt/security-stack && docker compose ps'
```

View recent logs:

```bash
pct exec 120 -- bash -lc 'cd /opt/media-stack && docker compose logs --tail=100'
```

## Notes about specific utility apps

### Monitoring

- Uptime Kuma is for service checks and uptime alerts.
- Tautulli is for Plex monitoring and analytics.
- Homepage is a dashboard for linking your homelab apps.
- Scrutiny is included but disabled by default because disk health monitoring needs disk device access from the Proxmox host.

### Reverse proxy

- Nginx Proxy Manager is enabled by default.
- Caddy is included as an optional alternative.
- Do not enable Nginx Proxy Manager and Caddy together unless you change ports because both want `80` and `443`.
- Cloudflared is included but disabled because it requires a Cloudflare Tunnel token.

### Management

- Portainer is enabled by default for Docker management.
- Dozzle is enabled by default for container log viewing.
- Watchtower is included but disabled by default because unattended updates can break services.

### Security

- AdGuard Home is enabled by default.
- Pi-hole is included as an optional alternative.
- Do not enable AdGuard Home and Pi-hole together unless you change ports because both want DNS port `53`.
- Vaultwarden is enabled by default with signups allowed for initial setup. After creating your account, set `VAULTWARDEN_SIGNUPS_ALLOWED="false"` and update/redeploy.

## Troubleshooting

### Seerr will not open or fails to start

If the other apps open but Seerr does not, it is usually a permissions issue with the Seerr config directory.

The current script automatically prepares the Seerr config directory before first startup. If you need to repair an existing deployment manually, run:

```bash
pct exec 120 -- bash -lc 'mkdir -p /opt/media-stack/config/seerr && chown -R 1000:1000 /opt/media-stack/config/seerr'
pct exec 120 -- bash -lc 'cd /opt/media-stack && docker compose restart seerr'
```

Then open:

```text
http://YOUR-LXC-IP:5055
```

### Homepage does not show the new services

Run:

```bash
pct exec 130 -- bash -lc 'ls -lah /opt/monitoring-stack/config/homepage/services.yaml'
pct exec 130 -- bash -lc 'cd /opt/monitoring-stack && docker compose logs --tail=100 homepage'
```

Then reinstall the bundled services file:

```bash
./install-homepage-services.sh
```

## Removing failed test containers

```bash
pct destroy 120 --purge
pct destroy 130 --purge
pct destroy 140 --purge
pct destroy 150 --purge
pct destroy 160 --purge
```

If you changed `CTID`, replace the number with your container ID.
