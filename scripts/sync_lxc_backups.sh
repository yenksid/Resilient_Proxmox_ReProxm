#!/usr/bin/env bash
# =================================================================
# Proxmox Resilient LXC Backup Sync
#
# Validates backups, stages known-good copies, syncs to cloud,
# and alerts via n8n if anything goes wrong.
# =================================================================

set -Eeuo pipefail
IFS=$'\n\t'
LANG=C

# ----------------- Configuration (EDIT THESE) -----------------
LOCAL_DUMP_FOLDER="<PLACEHOLDER_LOCAL_DUMP_FOLDER>"        # e.g., /mnt/backup/dump
LOCAL_STAGING_FOLDER="<PLACEHOLDER_LOCAL_STAGING_FOLDER>"    # e.g., /mnt/backup/cloud_staging
REMOTE_FOLDER="<PLACEHOLDER_RCLONE_REMOTE>"                # e.g., gdrive:LXC_Backups
N8N_WEBHOOK_URL="<PLACEHOLDER_N8N_LXC_SYNC_WEBHOOK_URL>"     # e.g., http://<n8n-ip>:5678/webhook/lxc-sync
# --------------------------------------------------------------

log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

send_n8n_json() {
  local payload="$1"
  if [[ -n "${N8N_WEBHOOK_URL:-}" ]]; then
    curl -fsS -X POST -H "Content-Type: application/json" --data-raw "$payload" "$N8N_WEBHOOK_URL" || true
  fi
}

log "Starting verified cloud backup process..."
FAILED_BACKUPS=0
SUCCESS_BACKUPS=0
FAILED_REASONS=""

mkdir -p "$LOCAL_STAGING_FOLDER"
log "Verifying latest local backups..."

for lxc_id in $(pct list | awk 'NR>1 {print $1}'); do
    LATEST_TAR=$(ls -1 "$LOCAL_DUMP_FOLDER"/vzdump-lxc-"$lxc_id"-*.tar.zst 2>/dev/null | tail -n 1)

    if [ -z "$LATEST_TAR" ]; then
        log "No backups found for $lxc_id, skipping."
        continue
    fi

    BASENAME_TAR=$(basename "$LATEST_TAR")
    BASENAME_NOTES="${BASENAME_TAR}.notes"

    # --- Staging Verification ---
    STAGING_FILE_TAR="$LOCAL_STAGING_FOLDER/$BASENAME_TAR"
    STAGING_FILE_NOTES="$LOCAL_STAGING_FOLDER/$BASENAME_NOTES"

    if [ -f "$STAGING_FILE_TAR" ] && [ -f "$STAGING_FILE_NOTES" ]; then
        log "OK: $BASENAME_TAR already verified and staged. Skipping."
        SUCCESS_BACKUPS=$((SUCCESS_BACKUPS + 1))
        continue
    fi

    log "NEW: $BASENAME_TAR. Verifying integrity..."
    LOG_FILE="${LATEST_TAR%.tar.zst}.log"

    if grep -q "ERROR:" "$LOG_FILE"; then
        log "FAIL LOG! $BASENAME_TAR"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        FAILED_REASONS="$FAILED_REASONS\n- $BASENAME_TAR (Log contains errors)"
        continue
    fi

    if ! zstd -t "$LATEST_TAR"; then
        log "FAIL CORRUPT! $BASENAME_TAR"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        FAILED_REASONS="$FAILED_REASONS\n- $BASENAME_TAR (.tar.zst file corrupt)"
        continue
    fi

    log "OK: $BASENAME_TAR verified. Copying to staging..."
    cp "$LATEST_TAR" "$STAGING_FILE_TAR"
    cp "${LATEST_TAR}.notes" "$STAGING_FILE_NOTES"
    SUCCESS_BACKUPS=$((SUCCESS_BACKUPS + 1))
done

log "Verification complete. $SUCCESS_BACKUPS valid, $FAILED_BACKUPS failed."

# Sync staging with Google Drive
log "Starting rclone sync (old files will go to trash)..."
if ! rclone sync "$LOCAL_STAGING_FOLDER" "$REMOTE_FOLDER"; then
    log "RCLONE FAIL! Upload failed. Skipping trash cleanup."
    # Estandarizado a "fail" (inglés) para n8n
    send_n8n_json '{"status":"fail", "reason":"Rclone sync failed"}'
    exit 1
fi

log "Sync successful. Emptying Google Drive trash..."
rclone cleanup "$REMOTE_FOLDER"

log "Cloud backup process finished."

# Send final status to n8n
# Estandarizado a "success" (inglés) para n8n
STATUS_PAYLOAD=$(printf '{"status":"success", "success_count":%d, "fail_count":%d, "fail_reasons":"%s"}' \
    "$SUCCESS_BACKUPS" "$FAILED_BACKUPS" "$FAILED_REASONS")
send_n8n_json "$STATUS_PAYLOAD"