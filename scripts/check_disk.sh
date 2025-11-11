#!/usr/bin/env bash
# =================================================================
# Proxmox Resilient Disk Monitor (ReProxm)
# (EN) v2.0: Hardened with flock, traps, preflight, and persistent logging.
# (ES) v2.0: Endurecido con flock, traps, preflight y logging persistente.
# =================================================================

set -Eeuo pipefail
IFS=$'\n\t'
LANG=C
umask 027 # (EN) Log files not world-readable. (ES) Archivos de log no legibles por todos.

# ----------------- Configuration (EDIT THESE) -----------------
# ----------------- Configuración (EDITAR ESTO) -----------------
N8N_WEBHOOK_URL="<PLACEHOLDER_N8N_DISK_WEBHOOK_URL>"  # e.g., http://<n8n-ip>:5678/webhook/disk-alert
DISK_PATH="<PLACEHOLDER_DISK_PATH>"                 # e.g., /mnt/backup
THRESHOLD_PERCENT="90"                              # e.g., 90

# (EN) Log file will be created at <DISK_PATH>/logs/check_disk.log
# (ES) El archivo de log se creará en <DISK_PATH>/logs/check_disk.log
LOG_FILE="${DISK_PATH}/logs/check_disk.log"
# --------------------------------------------------------------

# --- (EN) logging and helpers defined BEFORE flock ---
# --- (ES) logging y helpers definidos ANTES del lock ---

# (EN) We must create the log dir *after* DISK_PATH is set, but define functions first.
# (ES) Debemos crear el dir de log *después* de definir DISK_PATH, pero definir las funciones primero.

log() {
  local message="$*"
  local timestamp
  timestamp=$(printf '[%(%Y-%m-%d %H:%M:%S)T]' -1)
  # (EN) Log to console and to file. (ES) Log a consola y archivo.
  echo "$timestamp $message" | tee -a "$LOG_FILE"
}

json_escape() {
  # (EN) Escape quotes, backslashes, and control characters for safe JSON payload.
  # (ES) Escapa comillas, barras y caracteres de control para un payload JSON seguro.
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
# --- (EN) End of helpers --- (ES) Fin de helpers ---

# --- (EN) Lockfile: Prevents cron overlap ---
# --- (ES) Lockfile: Previene solapamiento del cron ---
LOCKDIR="/var/lock"
[[ -d "$LOCKDIR" ]] || LOCKDIR="/run/lock"
exec 9>"$LOCKDIR/check_disk.lock"
if ! flock -n 9; then
  # (EN) log() cannot be used here yet, as LOG_FILE path is not validated.
  # (ES) log() no se puede usar aquí, ya que la ruta de LOG_FILE no está validada.
  echo "WARN: Another instance of check_disk.sh is running. Exiting."
  exit 0
fi

# --- (EN) Robust Debugger (ERR and Signal Traps) ---
# --- (ES) Debugger Robusto (Traps de ERR y Señales) ---
_on_error() {
  local exit_code=$?
  local line_number=$LINENO
  local command=$BASH_COMMAND
  log "--- ¡ERROR INESPERADO! ---"
  log "El script falló en la línea $line_number con el código $exit_code"
  log "Comando que falló: $command"
  local reason
  reason=$(printf "Error script linea %s (codigo %s): %s" "$line_number" "$exit_code" "$command")
  send_n8n_json "$(printf '{"status":"fail","reason":"%s"}' "$(json_escape "$reason")")"
}
trap _on_error ERR

_on_term() {
  log "--- ¡INTERRUMPIDO POR SEÑAL! (SIGINT/SIGTERM) ---"
  send_n8n_json '{"status":"fail","reason":"Script interrumpido por señal (SIGTERM/SIGINT)"}'
  exit 130
}
trap _on_term INT TERM
# --- (EN) End of Debugger --- (ES) Fin del Debugger ---

# --- (EN) Preflight Check --- (ES) Chequeo Pre-vuelo ---
preflight() {
  # (EN) Now that we are inside a function, we can use log() safely
  # (ES) Ahora que estamos en una función, podemos usar log()
  
  # (EN) Create log directory *after* DISK_PATH is set
  # (ES) Crear dir de log *después* de definir DISK_PATH
  mkdir -p "$(dirname "$LOG_FILE")"

  log "Ejecutando chequeos pre-vuelo..."
  for bin in df awk sed curl printf mkdir; do
    command -v "$bin" >/dev/null || { log "Dependencia crítica faltante: $bin"; exit 127; }
  done
  
  [[ -d "$DISK_PATH" ]] || { log "¡FATAL! El directorio no existe: $DISK_PATH"; exit 11; }
  [[ -r "$DISK_PATH" ]] || { log "¡FATAL! Sin permiso de lectura en: $DISK_PATH"; exit 11; }
  [[ -w "$(dirname "$LOG_FILE")" ]] || { log "¡FATAL! Sin permiso de escritura en $(dirname "$LOG_FILE")"; exit 11; }
  log "Chequeos pre-vuelo superados."
}

SCRIPT_START_TIME=$(date +%s)
log "================================================="
log "Iniciando monitor de disco (v2.0)"

preflight

# (EN) Get usage as a plain number
# (ES) Obtener uso como un número simple
if ! OUT=$(df -P "$DISK_PATH" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}'); then
  log "FAIL: df no pudo leer $DISK_PATH"
  send_n8n_json "$(printf '{"status":"fail","reason":"df failed on path %s"}' "$DISK_PATH")"
  exit 1
fi

if ! [[ "$OUT" =~ ^[0-9]+$ ]]; then
  log "FAIL: no se pudo parsear el uso del disco para $DISK_PATH (obtenido: $OUT)"
  send_n8n_json "$(printf '{"status":"fail","reason":"invalid usage %s"}' "$OUT")"
  exit 1
fi

USAGE="$OUT"
# (EN) Compare usage against threshold
# (ES) Comparar uso contra el umbral
if (( USAGE > THRESHOLD_PERCENT )); then
  log "ALERTA: $DISK_PATH está al ${USAGE}% (> ${THRESHOLD_PERCENT}%)."
  send_n8n_json "$(printf '{"status":"alert","path":"%s","usage":%d,"threshold":%d}' "$DISK_PATH" "$USAGE" "$THRESHOLD_PERCENT")"
else
  log "OK: $DISK_PATH uso al ${USAGE}% (<= ${THRESHOLD_PERCENT}%)."
fi

SCRIPT_END_TIME=$(date +%s)
log "--- Ejecución total del script: $((SCRIPT_END_TIME - SCRIPT_START_TIME)) segundos."
log "================================================="

# (EN) Disable traps on clean exit
# (ES) Desactivar traps al salir limpiamente
trap - ERR INT TERM