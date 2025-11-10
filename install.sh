#!/usr/bin/env bash
# =================================================================
# Proxmox Resilient Kit Installer
#
# Installs and configures the full backup/verification/monitoring
# toolkit: dependencies, script deployment, placeholder injection,
# and cron scheduling.
# =================================================================

set -Eeuo pipefail
IFS=$'\n\t'
LANG=C

# -------------------- Colored logging --------------------
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'

log_info()    { printf "\n${C_CYAN}%s${C_RESET}\n" "$*"; }
log_success() { printf "${C_GREEN}%s${C_RESET}\n" "$*"; }
log_warn()    { printf "${C_YELLOW}%s${C_RESET}\n" "$*"; }
log_error()   { printf "${C_RED}ERROR: %s${C_RESET}\n" "$*" >&2; exit 1; }

# -------------------- Root check --------------------
if (( EUID != 0 )); then
  log_error "This installer must run as root (or with sudo)."
fi

# -------------------- Paths --------------------
# Assumes install.sh is at the repo root, with ./scripts beside it.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SCRIPTS_SOURCE_DIR="$SCRIPT_DIR/scripts"
SCRIPTS_DEST_DIR="/root"

SYNC_SCRIPT="$SCRIPTS_DEST_DIR/sync_lxc_backups.sh"
HOST_SCRIPT="$SCRIPTS_DEST_DIR/backup_host.sh"
DISK_SCRIPT="$SCRIPTS_DEST_DIR/check_disk.sh"

# -------------------- Helpers --------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || log_error "Missing dependency: $1"
}

ask() {
  # ask "Prompt" "default" -> echoes answer (default if empty)
  local prompt="$1" default="${2:-}"
  local answer
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " answer || true
    echo "${answer:-$default}"
  else
    read -r -p "$prompt: " answer || true
    echo "$answer"
  fi
}

sed_escape() {
  # Escape backslashes and ampersands for sed replacement
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//&/\\&}"
  printf '%s' "$s"
}

safe_copy() {
  # Copies $1 -> $2 backing up existing target
  local src="$1" dst="$2"
  if [[ ! -f "$src" ]]; then
    log_error "Source file not found: $src"
  fi
  if [[ -f "$dst" ]]; then
    cp -a "$dst" "${dst}.bak.$(date +%Y%m%d%H%M%S)"
  fi
  cp -a "$src" "$dst"
}

replace_placeholder() {
  # replace_placeholder <file> <placeholder> <value>
  local file="$1" placeholder="$2" value="$3"
  value="$(sed_escape "$value")"
  sed -i "s|${placeholder}|${value}|g" "$file"
}

install_dependencies() {
  log_info "Installing dependencies (rclone, zstd)..."
  require_cmd apt || log_error "apt not found. This installer targets Debian/Proxmox hosts."
  apt update >/dev/null 2>&1
  if ! apt install -y rclone zstd >/dev/null 2>&1; then
    log_error "Failed to install dependencies. Try: apt install -y rclone zstd"
  fi
  log_success "Dependencies installed."
  require_cmd rclone
  require_cmd zstd
  require_cmd crontab
}

ask_questions() {
  log_info "Configuration — please answer the prompts below."

  # 1) Disk path (base mount for all local data)
  DISK_PATH="$(ask 'Path to your backup disk (e.g., /mnt/backup)' '/mnt/backup')"
  [[ -n "$DISK_PATH" ]] || log_error "Backup disk path cannot be empty."

  # Create common directories proactively
  mkdir -p "$DISK_PATH"/{dump,cloud_staging,host_backup}

  # 2) rclone remote target
  RCLONE_NAME="$(ask "Your rclone remote name (e.g., gdrive)" "gdrive")"
  RCLONE_FOLDER="$(ask "Folder name in the cloud (e.g., LXC_Backups)" "LXC_Backups")"
  RCLONE_REMOTE="${RCLONE_NAME}:${RCLONE_FOLDER}"

  # 3) n8n webhooks
  log_warn "Use your n8n INTERNAL IP in webhook URLs (e.g., http://10.0.0.62:5678/webhook/...) to avoid NAT loopback issues."
  N8N_LXC_URL="$(ask 'n8n Webhook URL for LXC alerts'  '')"
  N8N_HOST_URL="$(ask 'n8n Webhook URL for Host backup alerts'  '')"
  N8N_DISK_URL="$(ask 'n8n Webhook URL for Disk alerts'  '')"

  # 4) Optional thresholds/tags/retention
  THRESHOLD_PERCENT="$(ask 'Disk usage alert threshold (%)' '90')"
  HOST_TAG="$(ask 'Host backup tag prefix' 'pmox-host')"
  KEEP_DAYS="$(ask 'Days to keep host backups' '7')"

  # Basic sanity
  [[ "$THRESHOLD_PERCENT" =~ ^[0-9]+$ ]] || log_error "Threshold must be a number."
  [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]] || log_error "Keep days must be a number."
}

copy_and_configure_scripts() {
  log_info "Copying and configuring scripts into $SCRIPTS_DEST_DIR ..."

  [[ -d "$SCRIPTS_SOURCE_DIR" ]] || log_error "Scripts folder not found: $SCRIPTS_SOURCE_DIR"

  safe_copy "$SCRIPTS_SOURCE_DIR/sync_lxc_backups.sh" "$SYNC_SCRIPT"
  safe_copy "$SCRIPTS_SOURCE_DIR/backup_host.sh"      "$HOST_SCRIPT"
  safe_copy "$SCRIPTS_SOURCE_DIR/check_disk.sh"       "$DISK_SCRIPT"

  chmod +x "$SYNC_SCRIPT" "$HOST_SCRIPT" "$DISK_SCRIPT"

  # Inject placeholders — keep in sync with script placeholder names
  # sync_lxc_backups.sh
  replace_placeholder "$SYNC_SCRIPT" "<PLACEHOLDER_LOCAL_DUMP_FOLDER>"        "$DISK_PATH/dump"
  replace_placeholder "$SYNC_SCRIPT" "<PLACEHOLDER_LOCAL_STAGING_FOLDER>"     "$DISK_PATH/cloud_staging"
  replace_placeholder "$SYNC_SCRIPT" "<PLACEHOLDER_RCLONE_REMOTE>"            "$RCLONE_REMOTE"
  replace_placeholder "$SYNC_SCRIPT" "<PLACEHOLDER_N8N_LXC_SYNC_WEBHOOK_URL>" "$N8N_LXC_URL"

  # backup_host.sh
  replace_placeholder "$HOST_SCRIPT" "<PLACEHOLDER_HOST_BACKUP_DEST_DIR>"     "$DISK_PATH/host_backup"
  #replace_placeholder "$HOST_SCRIPT" "<PLACEHOLDER_HOST_SOURCES>"             "\"/etc\" \"/root\""
  replace_placeholder "$HOST_SCRIPT" "<PLACEHOLDER_HOST_SOURCES>"             "/etc /root"
  replace_placeholder "$HOST_SCRIPT" "<PLACEHOLDER_KEEP_DAYS>"                "$KEEP_DAYS"
  replace_placeholder "$HOST_SCRIPT" "<PLACEHOLDER_N8N_HOST_WEBHOOK_URL>"     "$N8N_HOST_URL"
  replace_placeholder "$HOST_SCRIPT" "<PLACEHOLDER_HOST_TAG>"                 "$HOST_TAG"

  # check_disk.sh
  replace_placeholder "$DISK_SCRIPT" "<PLACEHOLDER_N8N_DISK_WEBHOOK_URL>"     "$N8N_DISK_URL"
  replace_placeholder "$DISK_SCRIPT" "<PLACEHOLDER_DISK_PATH>"                "$DISK_PATH"
  replace_placeholder "$DISK_SCRIPT" "<PLACEHOLDER_THRESHOLD_PERCENT>"        "$THRESHOLD_PERCENT"

  log_success "Scripts deployed and configured."
}

setup_cron() {
  log_info "Configuring cron jobs for root ..."

  local MARK_START="# >>> PROXMOX_RESILIENT_KIT"
  local MARK_END="# <<< PROXMOX_RESILIENT_KIT"
  local CRON_BLOCK="
$MARK_START
# 4:00 AM: Back up the Proxmox host configuration
0 4 * * * /root/backup_host.sh >/dev/null 2>&1
# 4:30 AM: Verify and sync LXC backups to the cloud
30 4 * * * /root/sync_lxc_backups.sh >/dev/null 2>&1
# 5:00 AM: Auto-update the Proxmox host
0 5 * * * apt update && apt dist-upgrade -y >/dev/null 2>&1
# 6:00 AM: Check free space on the main backup disk
0 6 * * * /root/check_disk.sh >/dev/null 2>&1
$MARK_END
"

  # Read current crontab (may be empty), remove existing block, append fresh block
  local CUR
  CUR="$(crontab -l 2>/dev/null || true)"

  # Remove any previous managed section
  CUR="$(printf '%s\n' "$CUR" | awk -v s="$MARK_START" -v e="$MARK_END" '
    BEGIN {skip=0}
    index(\$0,s){skip=1; next}
    index(\$0,e){skip=0; next}
    skip==0{print}
  ')"

  # Compose new crontab and install
  printf '%s\n%s\n' "$CUR" "$CRON_BLOCK" | crontab -
  log_success "Cron jobs installed."
}

main() {
  install_dependencies
  ask_questions
  copy_and_configure_scripts
  setup_cron

  log_info  "------------------------------------------------"
  log_success "Installation Complete!"
  log_info  "FINAL STEPS:"
  log_warn  "1) Run 'rclone config' and ensure a remote named '$RCLONE_NAME' exists (points to '$RCLONE_FOLDER')."
  log_warn  "2) Import and ACTIVATE the JSON workflows from '/n8n_workflows' in your n8n instance."
  log_info  "------------------------------------------------"
}

main
