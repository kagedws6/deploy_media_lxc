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

### 3. Paste the script contents

Paste the full contents of `deploy-media-lxc-configurable.sh` into the nano editor.

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

Each app has a toggle near the top of the script.

Use `1` to enable an app and `0` to disable it:

```bash
ENABLE_SONARR="1"
ENABLE_RADARR="1"
ENABLE_SABNZBD="1"
ENABLE_SEERR="1"
ENABLE_PROWLARR="1"
ENABLE_LIDARR="1"
ENABLE_BAZARR="1"
ENABLE_LAZYLIBRARIAN="1"
ENABLE_KAVITA="1"
ENABLE_AUDIOBOOKSHELF="1"
```

Optional apps are included but disabled by default:

```bash
ENABLE_QBITTORRENT="0"
ENABLE_GLUTUN="0"
ENABLE_AUTOBRR="0"
```

> Gluetun requires VPN-specific configuration before it should be enabled.

### 6. Make the script executable

Run:

```bash
chmod +x deploy-media-lxc.sh
```

### 7. Run the script

Run:

```bash
./deploy-media-lxc.sh
```

The script will:

1. Download a Debian LXC template if needed.
2. Create the Proxmox LXC container.
3. Add media and downloads bind mounts.
4. Install Docker and Docker Compose inside the LXC.
5. Generate a Docker Compose file based on the enabled app toggles.
6. Pull and start the selected containers.
7. Print the web UI links at the end.

### 8. View the deployment log

The script writes a log file on the Proxmox host:

```bash
cat /root/deploy-media-lxc-120.log
```

To view only the end of the log:

```bash
tail -n 80 /root/deploy-media-lxc-120.log
```

If you changed `CTID`, the log filename will use that CTID.

### 9. Check container status

After deployment, check the Docker containers with:

```bash
pct exec 120 -- bash -lc 'cd /opt/media-stack && docker compose ps'
```

View recent app logs:

```bash
pct exec 120 -- bash -lc 'cd /opt/media-stack && docker compose logs --tail=100'
```

If you changed `CTID`, replace `120` with your container ID.

## Default web ports

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

## Removing a failed test container

If a test run fails and you want to start clean, remove the container with:

```bash
pct destroy 120 --purge
```

Then rerun the script.

If you changed `CTID`, replace `120` with your container ID.
