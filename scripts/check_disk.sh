#!/usr/bin/env bash
# =================================================================
# Proxmox Resilient Disk Monitor
#
# Checks a mount's usage and alerts n8n if it exceeds a threshold.
# =================================================================

set -Eeuo pipefail
IFS=$'\n\t'
LANG=C

# ----------------- Configuration (EDIT THESE) -----------------
N8N_WEBHOOK_URL="<PLACEHOLDER_N8N_DISK_WEBHOOK_URL>"  # e.g., http://<n8n-ip>:5678/webhook/disk-alert
DISK_PATH="<PLACEHOLDER_DISK_PATH>"                 # e.g., /mnt/backup
THRESHOLD_PERCENT="90"                              # e.g., 90
# --------------------------------------------------------------

log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

require_set() {
  local name="$1" value="$2"
  if [[ -z "$value" || "$value" == "<PLACEHOLDER_"*">" ]]; then
    log "Config not set: $name"
    exit 1
  fi
}

send_n8n_json() {
  local payload="$1"
  if [[ -n "${N8N_WEBHOOK_URL:-}" ]]; then
    curl -fsS -X POST -H "Content-Type: application/json" --data-raw "$payload" "$N8N_WEBHOOK_URL" || true
  fi
}

require_set "DISK_PATH" "$DISK_PATH"
require_set "N8N_WEBHOOK_URL" "$N8N_WEBHOOK_URL"

# Get usage as a plain number
if ! OUT=$(df -P "$DISK_PATH" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}'); then
  log "FAIL: df could not read $DISK_PATH"
  send_n8n_json "$(printf '{"status":"fail","reason":"df failed on path %s"}' "$DISK_PATH")"
  exit 1
fi

if ! [[ "$OUT" =~ ^[0-9]+$ ]]; then
  log "FAIL: could not parse disk usage for $DISK_PATH (got: $OUT)"
  send_n8n_json "$(printf '{"status":"fail","reason":"invalid usage %s"}' "$OUT")"
  exit 1
fi

USAGE="$OUT"
if (( USAGE > THRESHOLD_PERCENT )); then
  log "ALERT: $DISK_PATH at ${USAGE}% (> ${THRESHOLD_PERCENT}%)."
  send_n8n_json "$(printf '{"status":"alert","path":"%s","usage":%d,"threshold":%d}' "$DISK_PATH" "$USAGE" "$THRESHOLD_PERCENT")"
else
  log "OK: $DISK_PATH usage ${USAGE}% (<= ${THRESHOLD_PERCENT}%)."
fi