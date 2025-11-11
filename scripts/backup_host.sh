#!/usr/bin/env bash
# =================================================================
# Proxmox Resilient Host Backup (ReProxm)
#
# v2.0: Hardened with flock, traps, preflight, logging, and integrity check.
# v2.0: Endurecido con flock, traps, preflight, logging y chequeo de integridad.
# =================================================================

set -Eeuo pipefail
IFS=$'\n\t'
LANG=C
umask 027 # (EN) Log files not world-readable. (ES) Archivos de log no legibles por todos.

# ----------------- Configuration (EDIT THESE) -----------------
DEST_DIR="<PLACEHOLDER_HOST_BACKUP_DEST_DIR>"        # e.g., /mnt/backup/host_backup
SOURCES_TO_BACKUP=( <PLACEHOLDER_HOST_SOURCES> )       # e.g., ( "/etc" "/root" )
KEEP_DAYS="<PLACEHOLDER_KEEP_DAYS>"                 # e.g., 7
N8N_WEBHOOK_URL="<PLACEHOLDER_N8N_HOST_WEBHOOK_URL>"  # e.g., http://<n8n-ip>:5678/webhook/host-backup
HOST_TAG="<PLACEHOLDER_HOST_TAG>"                   # e.g., pmox-host
LOG_FILE="<PLACEHOLDER_LOG_FILE_PATH>"              # e.g., /mnt/backup/logs/backup_host.log
DRYRUN=${DRYRUN:-0}
# --------------------------------------------------------------

# --- logging y helpers definidos ANTES del lock ---
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  local message="$*"
  local timestamp
  timestamp=$(printf '[%(%Y-%m-%d %H:%M:%S)T]' -1)
  echo "$timestamp $message" | tee -a "$LOG_FILE" >&2
}

json_escape() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

send_n8n_json() {
  local payload="$1"
  if [[ -n "${N8N_WEBHOOK_URL:-}" && "${N8N_WEBHOOK_URL}" != "<PLACEHOLDER_"*">" ]]; then
    curl -fsS -X POST -H "Content-Type: application/json" --data-raw "$payload" "$N8N_WEBHOOK_URL" || true
  fi
}
# --- Fin de helpers ---

# --- Lockfile ---
LOCKDIR="/var/lock"
[[ -d "$LOCKDIR" ]] || LOCKDIR="/run/lock"
exec 9>"$LOCKDIR/backup_host.lock"
if ! flock -n 9; then
  log "Otra instancia en ejecución; saliendo."
  exit 0
fi

# --- Definiciones de comandos (para DRYRUN) ---
FILENAME="${HOST_TAG}-$(date +%Y-%m-%d).tar.gz"
DEST_FILE="$DEST_DIR/$FILENAME"

tar_cmd=(tar --numeric-owner -czf "$DEST_FILE" "${SOURCES_TO_BACKUP[@]}")
gzip_cmd=(gzip -t "$DEST_FILE")
find_cmd=(find "$DEST_DIR" -type f -name "${HOST_TAG}-*.tar.gz" -mtime +"$KEEP_DAYS" -delete)
DRYRUN_MODE="real"

if (( DRYRUN )); then
  log "=== MODO DRYRUN ACTIVADO ==="
  log "No se crearán archivos (tar) ni se borrarán (find)."
  tar_cmd=(echo "DRYRUN: tar ... to $DEST_FILE")
  gzip_cmd=(echo "DRYRUN: gzip -t $DEST_FILE")
  find_cmd=(echo "DRYRUN: find ... -delete")
  DRYRUN_MODE="dryrun"
fi
# --- Fin Definiciones de comandos ---

# --- Debugger Robusto (ERR y Señales) ---
_on_error() {
  local exit_code=$?
  local line_number=$LINENO
  local command=$BASH_COMMAND
  log "--- ¡ERROR INESPERADO! ---"
  log "El script falló en la línea $line_number con el código $exit_code"
  log "Comando que falló: $command"
  local reason
  reason=$(printf "Error script linea %s (codigo %s): %s" "$line_number" "$exit_code" "$command")
  send_n8n_json "$(printf '{"status":"fail","mode":"%s","reason":"%s"}' "$DRYRUN_MODE" "$(json_escape "$reason")")"
}
trap _on_error ERR

_on_term() {
  log "--- ¡INTERRUMPIDO POR SEÑAL! (SIGINT/SIGTERM) ---"
  send_n8n_json "$(printf '{"status":"fail","mode":"%s","reason":"Script interrumpido por señal (SIGTERM/SIGINT)"}' "$DRYRUN_MODE")"
  exit 130
}
trap _on_term INT TERM
# --- Fin del Debugger ---

# --- Preflight Check ---
preflight() {
  log "Ejecutando chequeos pre-vuelo..."
  for bin in tar gzip find curl date mkdir; do
    command -v "$bin" >/dev/null || { log "Dependencia crítica faltante: $bin"; exit 127; }
  done
  
  for d in "$DEST_DIR" "$(dirname "$LOG_FILE")"; do
    [[ -d "$d" ]] || { log "¡FATAL! El directorio no existe: $d"; exit 11; }
    [[ -w "$d" ]] || { log "¡FATAL! Sin permiso de escritura en: $d"; exit 11; }
  done
  
  log "Chequeos pre-vuelo superados."
}

SCRIPT_START_TIME=$(date +%s)
log "================================================="
log "Iniciando backup del host (v2.0)"

preflight
mkdir -p "$DEST_DIR"

log "Creando archivo de configuración: $DEST_FILE"
if ! "${tar_cmd[@]}"; then
  log "FAIL: tar falló durante la creación del archivo."
  exit 1
fi

log "Verificando integridad del archivo: $DEST_FILE"
if ! "${gzip_cmd[@]}"; then
    log "FAIL: ¡El archivo $DEST_FILE está corrupto!"
    exit 1
fi

log "Archivo completado y verificado."

log "Eliminando backups de más de $KEEP_DAYS día(s) en $DEST_DIR ..."
"${find_cmd[@]}" || true

log "Backup del host finalizado."

send_n8n_json "$(printf '{"status":"exito","mode":"%s"}' "$DRYRUN_MODE")" # Estandarizado a "exito"

SCRIPT_END_TIME=$(date +%s)
log "--- Ejecución total del script: $((SCRIPT_END_TIME - SCRIPT_START_TIME)) segundos."
log "================================================="

trap - ERR INT TERM