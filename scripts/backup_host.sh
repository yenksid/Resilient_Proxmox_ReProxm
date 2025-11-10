#!/usr/bin/env bash
# =================================================================
# Proxmox Resilient Host Backup
#
# Archives critical host config (/etc and /root by default),
# keeps a rolling retention, and notifies n8n.
# =================================================================

set -Eeuo pipefail
IFS=$'\n\t'
LANG=C

# ----------------- Configuration (EDIT THESE) -----------------
DEST_DIR="<PLACEHOLDER_HOST_BACKUP_DEST_DIR>"        # e.g., /mnt/backup/host_backup
SOURCES_TO_BACKUP=("/etc" "/root")                     # e.g., ("/etc" "/root" "/var/lib/pve-cluster")
KEEP_DAYS="7"                                        # e.g., 7
N8N_WEBHOOK_URL="<PLACEHOLDER_N8N_HOST_WEBHOOK_URL>"  # e.g., http://<n8n-ip>:5678/webhook/host-backup
HOST_TAG="pmox-host"                                 # e.g., pmox-host
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
  # No comprobar el placeholder; enviar siempre si la URL está configurada
  if [[ -n "${N8N_WEBHOOK_URL:-}" ]]; then
    curl -fsS -X POST -H "Content-Type: application/json" --data-raw "$payload" "$N8N_WEBHOOK_URL" || true
  fi
}

# Comprobar solo las variables que el script no puede adivinar
require_set "DEST_DIR" "$DEST_DIR"
require_set "N8N_WEBHOOK_URL" "$N8N_WEBHOOK_URL"

mkdir -p "$DEST_DIR"

FILENAME="${HOST_TAG}-$(date +%Y-%m-%d).tar.gz"
DEST_FILE="$DEST_DIR/$FILENAME"

log "Creating host config archive: $DEST_FILE"
# Se eliminaron las banderas --xattrs y --acls para compatibilidad con NTFS
if tar --numeric-owner -czf "$DEST_FILE" "${SOURCES_TO_BACKUP[@]}"; then
  log "Archive complete."
  send_n8n_json '{"status":"success"}'
else
  log "FAIL: tar failed."
  send_n8n_json '{"status":"fail","reason":"tar command failed"}'
  exit 1
fi

log "Pruning backups older than $KEEP_DAYS day(s) in $DEST_DIR ..."
find "$DEST_DIR" -type f -name "${HOST_TAG}-*.tar.gz" -mtime +"$KEEP_DAYS" -delete || true

log "Host backup finished."