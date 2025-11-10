#!/usr/bin/env bash
# =================================================================
# Proxmox Resilient LXC Backup Sync (ReProxm)
#
# v4.7: Adds bilingual (EN/ES) inline documentation. No functional changes from v4.6.
# v4.7: Añade documentación bilingüe (EN/ES) en línea. Sin cambios funcionales sobre v4.6.
#
# Validates backups, stages known-good copies, syncs to cloud,
# and alerts via n8n if anything goes wrong.
# Valida backups, prepara copias fiables (staging), sincroniza con la nube,
# y alerta vía n8n si algo falla.
# =================================================================

set -Eeuo pipefail
IFS=$'\n\t'
LANG=C
umask 027 # (EN) Log/staging files not world-readable. (ES) Logs/staging no legibles por todos.

# ----------------- Configuration (EDIT THESE) -----------------
# ----------------- Configuración (EDITAR ESTO) -----------------

LOCAL_DUMP_FOLDER="/mnt/disco8tb/dump"
LOCAL_STAGING_FOLDER="/mnt/disco8tb/cloud_staging"
REMOTE_FOLDER="gdrive:LXC_Backups"
N8N_WEBHOOK_URL="http://10.0.0.62:5678/webhook/rclone-lxc-sync-status"
LOG_FILE="/mnt/disco8tb/logs/sync_lxc_backups.log"
DRYRUN=${DRYRUN:-0} # (EN) Run with 'DRYRUN=1 ...' to test. (ES) Ejecutar con 'DRYRUN=1 ...' para probar.
# --------------------------------------------------------------

# --- Logging and Helpers (defined before flock) ---
# --- Logging y Helpers (definidos ANTES del lock) ---
mkdir -p "$(dirname "$LOG_FILE")"

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
  if [[ -n "${N8N_WEBHOOK_URL:-}" ]]; then
    # (EN) Silent on success, show error on fail, non-blocking.
    # (ES) Silencioso en éxito, muestra error si falla, no bloqueante.
    curl -fsS -X POST -H "Content-Type: application/json" --data-raw "$payload" "$N8N_WEBHOOK_URL" || true
  fi
}

wait_stable_size() {
  # (EN) Waits for a file's size to be stable before processing.
  # (ES) Espera a que el tamaño de un archivo sea estable antes de procesarlo.
  local f=$1; local tries=${2:-3}; local wait=${3:-3}
  local s1 s2
  log "Verificando tamaño estable para $(basename "$f")..."
  for ((i=0;i<tries;i++)); do
    s1=$(stat -c %s "$f") || return 1
    sleep "$wait"
    s2=$(stat -c %s "$f") || return 1
    [[ "$s1" == "$s2" ]] && return 0 # (EN) Success, size is stable. (ES) Éxito, tamaño estable.
  done
  log "WARN: El tamaño de $(basename "$f") sigue cambiando. ($s1 != $s2)"
  return 1 # (EN) Fail, size not stable. (ES) Fallo, tamaño no estable.
}
# --- Fin de helpers ---

# --- Lockfile ---
# (EN) Robust lockdir fallback. (ES) Lockdir robusto con fallback.
LOCKDIR="/var/lock"
[[ -d "$LOCKDIR" ]] || LOCKDIR="/run/lock"
exec 9>"$LOCKDIR/sync_lxc_backups.lock"
if ! flock -n 9; then
  log "Otra instancia en ejecución; saliendo. (Lockfile busy)"
  exit 0
fi
# (EN) Lock is auto-released on script exit. (ES) El lock se libera al salir.

# --- Command Definitions (for DRYRUN) ---
# --- Definiciones de Comandos (para DRYRUN) ---
copy_cmd=(cp -f --reflink=auto --sparse=always)
rclone_cmd=(rclone sync "$LOCAL_STAGING_FOLDER" "$REMOTE_FOLDER"
  --log-file "${LOG_FILE}.rclone" --log-level INFO
  --retries 8 --retries-sleep 10s --timeout 5m --contimeout 30s
  --transfers 4 --checkers 16 --drive-chunk-size 128M
  --fast-list --drive-stop-on-upload-limit
  --drive-use-trash=false
  --include '*.tar.zst'
  --include '*.tar.zst.notes'
  --exclude '*'
)

DRYRUN_MODE="real"
if (( DRYRUN )); then
  log "=== MODO DRYRUN ACTIVADO ==="
  log "No se copiarán archivos (cp) ni se sincronizará con rclone (sync)."
  copy_cmd=(echo "DRYRUN: cp") # (EN) Replace 'cp' with 'echo'. (ES) Reemplaza 'cp' con 'echo'.
  rclone_cmd+=(--dry-run)      # (EN) Add --dry-run flag. (ES) Añade la bandera --dry-run.
  DRYRUN_MODE="dryrun"
fi
# --- Fin Definiciones de comandos ---

# --- Robust Error Traps (ERR & Signal) ---
# --- Traps de Error Robustos (ERR y Señal) ---
_on_error() {
  local exit_code=$?
  local line_number=$LINENO
  local command=$BASH_COMMAND
  
  log "--- ¡ERROR INESPERADO! ---"
  log "El script falló en la línea $line_number con el código $exit_code"
  log "Comando que falló: $command"
  
  local reason
  reason=$(printf "Error script linea %s (codigo %s): %s" "$line_number" "$exit_code" "$command")
  send_n8n_json "$(printf '{"status":"fallo","mode":"%s","reason":"%s"}' "$DRYRUN_MODE" "$(json_escape "$reason")")"
}
trap _on_error ERR

_on_term() {
  log "--- ¡INTERRUMPIDO POR SEÑAL! (SIGINT/SIGTERM) ---"
  send_n8n_json "$(printf '{"status":"fallo","mode":"%s","reason":"Script interrumpido por señal (SIGTERM/SIGINT)"}' "$DRYRUN_MODE")"
  exit 130
}
trap _on_term INT TERM
# --- Fin del Debugger ---

# --- Preflight Check ---
preflight() {
  log "Ejecutando chequeos pre-vuelo..."
  # (EN) 1. Check bins. (ES) 1. Verificar binarios.
  for bin in rclone zstd pct awk grep stat df curl cp touch sort tail; do
    command -v "$bin" >/dev/null || { log "Dependencia crítica faltante: $bin"; exit 127; }
  done
  
  # (EN) 2. Check dirs. (ES) 2. Verificar directorios.
  for d in "$LOCAL_DUMP_FOLDER" "$LOCAL_STAGING_FOLDER" "$(dirname "$LOG_FILE")"; do
    [[ -d "$d" ]] || { log "¡FATAL! El directorio no existe: $d"; exit 11; }
    [[ -w "$d" ]] || { log "¡FATAL! Sin permiso de escritura en: $d"; exit 11; }
  done
  
  # (EN) 3. Check remote. (ES) 3. Verificar remoto.
  log "Chequeando conexión con el 'remote' de rclone..."
  if ! rclone lsd "$REMOTE_FOLDER" >/dev/null 2>&1; then
    if (( DRYRUN )); then
        log "DRYRUN: Omitiendo creación de remote $REMOTE_FOLDER."
    else
        log "Remoto no encontrado; intentando crear carpeta en $REMOTE_FOLDER ..."
        rclone mkdir "$REMOTE_FOLDER" || {
          log "¡FATAL! No se pudo crear $REMOTE_FOLDER. ¿Credenciales/nombre del remote correctos?"
          exit 10
        }
    fi
  fi
  log "Chequeos pre-vuelo superados."
}

SCRIPT_START_TIME=$(date +%s)
log "================================================="
log "Iniciando proceso de backup verificado a la nube (v4.7)"

preflight

FAILED_BACKUPS=0
SUCCESS_BACKUPS=0
FAILED_REASONS=""

log "Verificando backups locales más recientes..."
VERIFY_START_TIME=$(date +%s)

# (EN) Safely map LXC IDs to array, ignoring pct list's exit code.
# (ES) Mapeo seguro de IDs de LXC a un array, ignorando el código de error de pct list.
if ! mapfile -t LXC_IDS < <(pct list | awk 'NR>1 {print $1}'); then
  log "¡FATAL! 'pct list' falló o no devolvió datos. ¿El servicio PVE está corriendo?"
  exit 12
fi

for lxc_id in "${LXC_IDS[@]}"; do
    
    # (EN) Robust file finding using nullglob.
    # (ES) Búsqueda robusta de archivos usando nullglob.
    shopt -s nullglob
    files=( "$LOCAL_DUMP_FOLDER"/vzdump-lxc-"$lxc_id"-*.tar.zst )
    shopt -u nullglob

    if (( ${#files[@]} == 0 )); then
      log "No se encontraron backups para $lxc_id, saltando."
      continue
    fi
    # (EN) Get newest file (lexical sort works for Proxmox timestamps).
    # (ES) Obtener el archivo más nuevo (el orden lexicográfico funciona).
    IFS=$'\n' read -r LATEST_TAR < <(printf '%s\n' "${files[@]}" | sort | tail -n 1)

    BASENAME_TAR=$(basename "$LATEST_TAR")
    BASENAME_NOTES="${BASENAME_TAR}.notes"
    STAGING_FILE_TAR="$LOCAL_STAGING_FOLDER/$BASENAME_TAR"
    STAGING_FILE_NOTES="$LOCAL_STAGING_FOLDER/$BASENAME_NOTES"

    # (EN) Staging check: If this exact verified backup is already staged, skip.
    # (ES) Verificación de Staging: Si este backup exacto ya está, saltar.
    if [ -f "$STAGING_FILE_TAR" ] && [ -f "$STAGING_FILE_NOTES" ]; then
        log "OK: $BASENAME_TAR ya está verificado y en staging. Saltando."
        SUCCESS_BACKUPS=$((SUCCESS_BACKUPS + 1))
        continue
    fi

    log "NUEVO: $BASENAME_TAR. Verificando integridad..."
    LOG_FILE_LXC="${LATEST_TAR%.tar.zst}.log"
    NOTES_FILE="${LATEST_TAR}.notes"

    # (EN) Check 1: Stable file size. (ES) Check 1: Tamaño de archivo estable.
    if ! wait_stable_size "$LATEST_TAR"; then
      log "FAIL: $BASENAME_TAR aún cambiando de tamaño; saltando este ciclo."
      FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
      FAILED_REASONS="$FAILED_REASONS\n- $BASENAME_TAR (archivo aún en escritura)"
      continue
    fi

    # (EN) Check 2: Log file exists. (ES) Check 2: El archivo .log existe.
    if [ ! -f "$LOG_FILE_LXC" ]; then
        log "¡FALLO! $BASENAME_TAR no tiene archivo .log. Marcando como corrupto."
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        FAILED_REASONS="$FAILED_REASONS\n- $BASENAME_TAR (Archivo .log faltante)"
        continue
    fi
    
    # (EN) Check 3: Log contains no errors. (ES) Check 3: El log no contiene errores.
    if grep -qi "ERROR:" "$LOG_FILE_LXC"; then
        log "FAIL LOG! $BASENAME_TAR"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        FAILED_REASONS="$FAILED_REASONS\n- $BASENAME_TAR (Log contains errors)"
        continue
    fi
    
    # (EN) Check 4: Log contains success mark. (ES) Check 4: El log contiene marca de éxito.
    if ! grep -Eqi "INFO:.*(backup finished|Finished Backup|Backup finished successfully)" "$LOG_FILE_LXC"; then
        log "FAIL LOG! $BASENAME_TAR sin marca de éxito en .log"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        FAILED_REASONS="$FAILED_REASONS\n- $BASENAME_TAR (sin 'finished' mark in log)"
        continue
    fi

    # (EN) Check 5: zstd integrity (multi-threaded). (ES) Check 5: Integridad zstd (multi-hilo).
    if ! zstd -t -T0 --no-progress "$LATEST_TAR"; then
        log "FAIL CORRUPT! $BASENAME_TAR (.tar.zst file corrupt)"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        FAILED_REASONS="$FAILED_REASONS\n- $BASENAME_TAR (.tar.zst file corrupt)"
        continue
    fi

    # (EN) Check 6: Enough space in staging. (ES) Check 6: Espacio suficiente en staging.
    size=$(stat -c %s "$LATEST_TAR")
    avail=$(df -PB1 "$LOCAL_STAGING_FOLDER" | awk 'NR==2{print $4}')
    if (( size > avail )); then
      log "FAIL SPACE! $BASENAME_TAR requiere $size bytes; disponibles $avail."
      FAILED_BACKUPS=$((FAILED_BACKUPS+1))
      FAILED_REASONS="$FAILED_REASONS\n- $BASENAME_TAR (sin espacio en staging)"
      continue
    fi

    # (EN) All checks passed. Copy to staging.
    # (ES) Todas las pruebas superadas. Copiando a staging.
    log "OK: $BASENAME_TAR verificado. Copiando a staging..."
    "${copy_cmd[@]}" "$LATEST_TAR" "$STAGING_FILE_TAR"
    
    if [ -f "$NOTES_FILE" ]; then
        "${copy_cmd[@]}" "$NOTES_FILE" "$STAGING_FILE_NOTES"
    else
        log "WARN: No se encontró $BASENAME_NOTES. Se creará uno vacío en staging."
        touch "$STAGING_FILE_NOTES"
    fi
    
    SUCCESS_BACKUPS=$((SUCCESS_BACKUPS + 1))
done

VERIFY_END_TIME=$(date +%s)
log "Verificación completada. $SUCCESS_BACKUPS válidos, $FAILED_BACKUPS fallidos."
log "--- Fase de Verificación/Staging tomó $((VERIFY_END_TIME - VERIFY_START_TIME)) segundos."

# (EN) Exit clean if no new files were processed.
# (ES) Salir limpiamente si no se procesaron archivos nuevos.
if (( SUCCESS_BACKUPS == 0 && FAILED_BACKUPS == 0 )); then
  log "Verificación completada. No hay archivos nuevos que procesar. Saliendo."
  STATUS_PAYLOAD=$(printf '{"status":"exito", "mode":"%s", "success_count":0, "fail_count":0, "fail_reasons":""}' "$DRYRUN_MODE")
  send_n8n_json "$STATUS_PAYLOAD"
  
  trap - ERR INT TERM # (EN) Disable traps before clean exit. (ES) Desactivar traps antes de salir.
  exit 0
fi

log "Iniciando rclone sync (borrado permanente)..."
SYNC_START_TIME=$(date +%s)

# (EN) Execute the rclone command array.
# (ES) Ejecutar el array de comandos rclone.
if ! "${rclone_cmd[@]}"; then
    log "RCLONE FAIL! Upload failed."
    exit 1 # (EN) Trap will catch this. (ES) El 'trap' capturará esto.
fi

SYNC_END_TIME=$(date +%s)
log "--- Fase de Rclone Sync tomó $((SYNC_END_TIME - SYNC_START_TIME)) segundos."
log "Proceso de backup a la nube finalizado."

# (EN) Send final success payload.
# (ES) Enviar payload final de éxito.
STATUS_PAYLOAD=$(printf '{"status":"exito", "mode":"%s", "success_count":%d, "fail_count":%d, "fail_reasons":"%s"}' \
    "$DRYRUN_MODE" "$SUCCESS_BACKUPS" "$FAILED_BACKUPS" "$(json_escape "$FAILED_REASONS")")
send_n8n_json "$STATUS_PAYLOAD"

SCRIPT_END_TIME=$(date +%s)
log "--- Ejecución total del script: $((SCRIPT_END_TIME - SCRIPT_START_TIME)) segundos."
log "================================================="

# (EN) Disable traps on clean exit.
# (ES) Desactivar traps al salir limpiamente.
trap - ERR INT TERM