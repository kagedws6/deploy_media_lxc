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
