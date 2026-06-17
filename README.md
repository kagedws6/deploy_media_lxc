# deploy_media_lxc

A configurable Proxmox LXC deployment script for spinning up a self-hosted media automation stack with Docker Compose.

## Included apps

- Sonarr
- Radarr
- Prowlarr
- SABnzbd
- Seerr
- Lidarr
- Bazarr
- LazyLibrarian
- Kavita
- Audiobookshelf

Optional toggles are included for qBittorrent, Gluetun, and Autobrr.

> This script is intended for homelab use. Review the script before running it, especially storage paths, LXC ID, privileged container settings, and VPN-related options.

## Available scripts

| Script | Default CTID | Purpose | Enabled by default |
|---|---:|---|---|
| `deploy-media-lxc.sh` | 120 | Media automation | Sonarr, Radarr, SABnzbd, Seerr, Prowlarr, Lidarr, Bazarr, LazyLibrarian, Kavita, Audiobookshelf |
| `deploy-monitoring-lxc.sh` | 130 | Monitoring and dashboards | Uptime Kuma, Tautulli, Homepage |
| `deploy-reverse-proxy-lxc.sh` | 140 | Reverse proxy / ingress | Nginx Proxy Manager |
| `deploy-management-lxc.sh` | 150 | Docker management and logs | Portainer, Dozzle |
| `deploy-security-lxc.sh` | 160 | DNS blocking and password vault | AdGuard Home, Vaultwarden |

Some apps are included but disabled by default because they require extra secrets, port planning, or device passthrough:

- qBittorrent, Gluetun, and Autobrr in the media script
- Scrutiny in the monitoring script
- Caddy and Cloudflared in the reverse proxy script
- Watchtower in the management script
- Pi-hole in the security script

## How to use

These steps are meant to be run from the **main Proxmox host console**, not from inside an LXC container or VM.

### 1. Open the Proxmox host shell

In the Proxmox web interface:

1. Select your Proxmox node in the left sidebar.
2. Click **Shell**.
3. Make sure you are at the Proxmox host prompt.

You can also connect over SSH:

```bash
ssh root@YOUR-PROXMOX-IP
```

### 2. Create the script file

Create a new script file with `nano`:

```bash
nano deploy-media-lxc.sh
```

For one of the utility stacks, use that script name instead, for example:

```bash
nano deploy-monitoring-lxc.sh
```

### 3. Paste the script contents

Paste the full contents of the script into the nano editor.

After pasting, save and exit:

```text
CTRL + O
ENTER
CTRL + X
```

### 4. Review and adjust the settings

Before running the script, review the settings near the top of the file.

Common values to check:

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

The media script also includes host bind-mount paths:

```bash
HOST_MEDIA_PATH="/mnt/media"
HOST_DOWNLOADS_PATH="/mnt/downloads"
```

Important notes:

- `CTID` must be unused.
- `ROOTFS_STORAGE` should match your Proxmox storage name, commonly `local-lvm`.
- `DISK_SIZE` should be a plain number, such as `64`, not `64G`.
- `HOST_MEDIA_PATH` and `HOST_DOWNLOADS_PATH` should point to storage paths on the Proxmox host.

You can check your available Proxmox storage names with:

```bash
pvesm status
```

### 5. Enable or disable apps

Each script has app toggles near the top.

Use `1` to enable an app and `0` to disable it:

```bash
ENABLE_SONARR="1"
ENABLE_RADARR="1"
ENABLE_SABNZBD="1"
ENABLE_SEERR="1"
```

Optional apps are usually disabled by default when they need extra setup:

```bash
ENABLE_GLUTEN="0"
ENABLE_CLOUDFLARED="0"
ENABLE_WATCHTOWER="0"
ENABLE_SCRUTINY="0"
```

> Gluetun requires VPN-specific configuration before it should be enabled. Cloudflared requires a tunnel token. Scrutiny requires host disk/S.M.A.R.T. device passthrough. Watchtower can auto-update containers, so enable it carefully.

### 6. Make the script executable

Run:

```bash
chmod +x deploy-media-lxc.sh
```

For a utility stack, use that filename instead:

```bash
chmod +x deploy-monitoring-lxc.sh
```

### 7. Run the script

Run:

```bash
./deploy-media-lxc.sh
```

Or for a utility stack:

```bash
./deploy-monitoring-lxc.sh
```

The script will:

1. Download a Debian LXC template if needed.
2. Create the Proxmox LXC container.
3. Install Docker and Docker Compose inside the LXC.
4. Generate a Docker Compose file based on the enabled app toggles.
5. Pull and start the selected containers.
6. Print the web UI links at the end.

The media script also adds media and downloads bind mounts.

### 8. View the deployment log

Each script writes a log file on the Proxmox host.

Examples:

```bash
cat /root/deploy-media-lxc-120.log
cat /root/deploy-monitoring-stack-130.log
cat /root/deploy-reverse-proxy-stack-140.log
cat /root/deploy-management-stack-150.log
cat /root/deploy-security-stack-160.log
```

To view only the end of a log:

```bash
tail -n 80 /root/deploy-media-lxc-120.log
```

If you changed `CTID`, the log filename will use that CTID.

### 9. Check container status

After deployment, check the Docker containers with:

```bash
pct exec 120 -- bash -lc 'cd /opt/media-stack && docker compose ps'
```

For the utility stacks:

```bash
pct exec 130 -- bash -lc 'cd /opt/monitoring-stack && docker compose ps'
pct exec 140 -- bash -lc 'cd /opt/reverse-proxy-stack && docker compose ps'
pct exec 150 -- bash -lc 'cd /opt/management-stack && docker compose ps'
pct exec 160 -- bash -lc 'cd /opt/security-stack && docker compose ps'
```

View recent app logs:

```bash
pct exec 120 -- bash -lc 'cd /opt/media-stack && docker compose logs --tail=100'
```

If you changed `CTID`, replace `120` with your container ID.

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

If you changed `CTID`, replace `120` with your container ID.

## Removing a failed test container

If a test run fails and you want to start clean, remove the container with:

```bash
pct destroy 120 --purge
```

For the utility stacks:

```bash
pct destroy 130 --purge
pct destroy 140 --purge
pct destroy 150 --purge
pct destroy 160 --purge
```

Then rerun the script.

If you changed `CTID`, replace the number with your container ID.
