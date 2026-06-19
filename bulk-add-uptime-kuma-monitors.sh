#!/usr/bin/env bash
set -Eeuo pipefail

# Bulk-adds the current homelab checks to Uptime Kuma.
# Run this on the Proxmox host.
#
# Requirements:
# - Monitoring LXC is CT 130 by default
# - Uptime Kuma container is named uptime-kuma
# - Uptime Kuma has already been initialized with a login
#
# This script asks for your Uptime Kuma login locally. It does not save it.

KUMA_CTID="${KUMA_CTID:-130}"
KUMA_CONTAINER="${KUMA_CONTAINER:-uptime-kuma}"
KUMA_URL="${KUMA_URL:-http://127.0.0.1:3001}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-60}"
RETRY_INTERVAL_SECONDS="${RETRY_INTERVAL_SECONDS:-60}"
MAX_RETRIES="${MAX_RETRIES:-3}"
DRY_RUN="${DRY_RUN:-0}"

read -r -p "Uptime Kuma username: " KUMA_USER
read -r -s -p "Uptime Kuma password: " KUMA_PASS
echo
read -r -p "Uptime Kuma 2FA code, if enabled (press Enter if not): " KUMA_2FA

if ! pct status "$KUMA_CTID" &>/dev/null; then
  echo "Container CT ${KUMA_CTID} was not found."
  exit 1
fi

if ! pct exec "$KUMA_CTID" -- docker ps --format '{{.Names}}' | grep -qx "$KUMA_CONTAINER"; then
  echo "Could not find Docker container '${KUMA_CONTAINER}' in CT ${KUMA_CTID}."
  exit 1
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry run only. No monitors will be added."
fi

TMP_JS="$(mktemp /tmp/uptime-kuma-import.XXXXXX.js)"
trap 'rm -f "$TMP_JS"' EXIT

cat > "$TMP_JS" <<'NODE'
const { io } = require("socket.io-client");

const config = {
  url: process.env.KUMA_URL || "http://127.0.0.1:3001",
  username: process.env.KUMA_USER,
  password: process.env.KUMA_PASS,
  twofa: process.env.KUMA_2FA || "",
  interval: Number(process.env.INTERVAL_SECONDS || 60),
  retryInterval: Number(process.env.RETRY_INTERVAL_SECONDS || 60),
  maxRetries: Number(process.env.MAX_RETRIES || 3),
  dryRun: process.env.DRY_RUN === "1",
};

if (!config.username || !config.password) {
  throw new Error("KUMA_USER and KUMA_PASS are required.");
}

const monitors = [
  // Infrastructure hosts
  { name: "[Host] Proxmox", type: "http", url: "https://192.168.1.102:8006", ignoreTls: true },
  { name: "[Host] Media LXC", type: "ping", hostname: "192.168.1.254" },
  { name: "[Host] Monitoring LXC", type: "ping", hostname: "192.168.1.184" },
  { name: "[Host] Reverse Proxy LXC", type: "ping", hostname: "192.168.1.225" },
  { name: "[Host] Management LXC", type: "ping", hostname: "192.168.1.208" },
  { name: "[Host] Security LXC", type: "ping", hostname: "192.168.1.245" },

  // Media
  { name: "[Media] Sonarr", type: "http", url: "http://192.168.1.254:8989" },
  { name: "[Media] Radarr", type: "http", url: "http://192.168.1.254:7878" },
  { name: "[Media] SABnzbd", type: "http", url: "http://192.168.1.254:8080" },
  { name: "[Media] Seerr", type: "http", url: "http://192.168.1.254:5055" },
  { name: "[Media] Prowlarr", type: "http", url: "http://192.168.1.254:9696" },
  { name: "[Media] Lidarr", type: "http", url: "http://192.168.1.254:8686" },
  { name: "[Media] Bazarr", type: "http", url: "http://192.168.1.254:6767" },
  { name: "[Media] LazyLibrarian", type: "http", url: "http://192.168.1.254:5299" },
  { name: "[Media] Kavita", type: "http", url: "http://192.168.1.254:5000" },
  { name: "[Media] Audiobookshelf", type: "http", url: "http://192.168.1.254:13378" },

  // Monitoring
  { name: "[Monitoring] Uptime Kuma", type: "http", url: "http://127.0.0.1:3001" },
  { name: "[Monitoring] Tautulli", type: "http", url: "http://192.168.1.184:8181" },
  { name: "[Monitoring] Homepage", type: "http", url: "http://192.168.1.184:3000" },

  // Network / management / security
  { name: "[Network] Nginx Proxy Manager", type: "http", url: "http://192.168.1.225:81" },
  { name: "[Management] Portainer", type: "http", url: "https://192.168.1.208:9443", ignoreTls: true },
  { name: "[Management] Dozzle", type: "http", url: "http://192.168.1.208:8088" },
  { name: "[Security] AdGuard Home", type: "http", url: "http://192.168.1.245:8083" },
  { name: "[Security] Vaultwarden", type: "http", url: "http://192.168.1.245:11001" },
];

function baseMonitor(item) {
  return {
    type: item.type,
    name: item.name,
    url: item.url || "",
    hostname: item.hostname || "",
    interval: config.interval,
    retryInterval: config.retryInterval,
    maxretries: config.maxRetries,
    resendInterval: 0,
    timeout: Math.max(30, Math.floor(config.interval * 0.8)),
    accepted_statuscodes: ["200-299"],
    active: true,
    upsideDown: false,
    ignoreTls: Boolean(item.ignoreTls),
    maxredirects: 10,
    notificationIDList: {},
    method: "GET",
    headers: "",
    body: "",
    httpBodyEncoding: "json",
    authMethod: "",
    parent: null,
    description: "",
    kafkaProducerBrokers: [],
    kafkaProducerSaslOptions: {},
    conditions: [],
    rabbitmqNodes: [],
    ping_numeric: false,
    ping_count: 1,
    ping_per_request_timeout: 10,
    packetSize: 56,
    saveResponse: false,
    saveErrorResponse: false,
    responseMaxLength: 512,
  };
}

function emitAck(socket, event, ...args) {
  return new Promise((resolve, reject) => {
    socket.emit(event, ...args, (response) => {
      if (response && response.ok) {
        resolve(response);
      } else {
        reject(new Error(response?.msg || `${event} failed`));
      }
    });
  });
}

async function main() {
  let monitorList = {};
  const socket = io(config.url, {
    transports: ["websocket"],
    timeout: 15000,
    reconnection: false,
  });

  socket.on("monitorList", (list) => {
    monitorList = list || {};
  });

  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Timed out connecting to Uptime Kuma.")), 15000);

    socket.on("connect_error", (err) => {
      clearTimeout(timer);
      reject(err);
    });

    socket.on("connect", async () => {
      try {
        const data = { username: config.username, password: config.password };
        if (config.twofa) data.token = config.twofa;

        socket.emit("login", data, (response) => {
          if (response?.ok) {
            clearTimeout(timer);
            resolve();
            return;
          }
          clearTimeout(timer);
          if (response?.tokenRequired) {
            reject(new Error("Uptime Kuma requires a 2FA code. Re-run and enter it when prompted."));
          } else {
            reject(new Error(response?.msg || "Login failed."));
          }
        });
      } catch (err) {
        clearTimeout(timer);
        reject(err);
      }
    });
  });

  // afterLogin pushes monitorList to the socket; give it a moment to arrive.
  await new Promise((resolve) => setTimeout(resolve, 1200));
  const existingNames = new Set(Object.values(monitorList).map((m) => m.name).filter(Boolean));

  let added = 0;
  let skipped = 0;

  for (const item of monitors) {
    if (existingNames.has(item.name)) {
      console.log(`SKIP  ${item.name} already exists`);
      skipped++;
      continue;
    }

    if (config.dryRun) {
      console.log(`PLAN  ${item.name}`);
      continue;
    }

    await emitAck(socket, "add", baseMonitor(item));
    console.log(`ADD   ${item.name}`);
    added++;
  }

  console.log("");
  console.log(config.dryRun
    ? `Dry run complete. ${monitors.length - skipped} monitor(s) would be added, ${skipped} already existed.`
    : `Import complete. Added ${added} monitor(s), skipped ${skipped} existing monitor(s).`);

  socket.disconnect();
}

main().catch((err) => {
  console.error(`ERROR: ${err.message}`);
  process.exit(1);
});
NODE

pct push "$KUMA_CTID" "$TMP_JS" "/tmp/uptime-kuma-bulk-import.js"

pct exec "$KUMA_CTID" -- docker cp \
  /tmp/uptime-kuma-bulk-import.js \
  "$KUMA_CONTAINER":/app/data/.uptime-kuma-bulk-import.js

pct exec "$KUMA_CTID" -- \
  env \
    KUMA_URL="$KUMA_URL" \
    KUMA_USER="$KUMA_USER" \
    KUMA_PASS="$KUMA_PASS" \
    KUMA_2FA="$KUMA_2FA" \
    INTERVAL_SECONDS="$INTERVAL_SECONDS" \
    RETRY_INTERVAL_SECONDS="$RETRY_INTERVAL_SECONDS" \
    MAX_RETRIES="$MAX_RETRIES" \
    DRY_RUN="$DRY_RUN" \
  docker exec \
    -e KUMA_URL \
    -e KUMA_USER \
    -e KUMA_PASS \
    -e KUMA_2FA \
    -e INTERVAL_SECONDS \
    -e RETRY_INTERVAL_SECONDS \
    -e MAX_RETRIES \
    -e DRY_RUN \
    "$KUMA_CONTAINER" \
    node /app/data/.uptime-kuma-bulk-import.js

pct exec "$KUMA_CTID" -- docker exec "$KUMA_CONTAINER" rm -f /app/data/.uptime-kuma-bulk-import.js >/dev/null 2>&1 || true
pct exec "$KUMA_CTID" -- rm -f /tmp/uptime-kuma-bulk-import.js >/dev/null 2>&1 || true
