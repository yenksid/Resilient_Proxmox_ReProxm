# Registro de Cambios

Todos los cambios relevantes de este proyecto se documentan en este archivo.

El formato se basa en **Keep a Changelog**  
y el proyecto sigue **Semantic Versioning** (SemVer).

---

## [v1.0.0] — 2025-11-12 — «Resiliencia»

Esta versión marca la transición de un host Proxmox fallido a un sistema de producción robusto, automatizado y monitoreado de forma continua.

### 🏥 Recuperación y Estabilidad del Host (Parche Crítico)

Se implementaron correcciones críticas para recuperar el servidor de un estado irrecuperable y garantizar la estabilidad operativa a largo plazo.

- **Recuperación de Arranque:** Se diagnosticó un fallo de arranque irrecuperable (`Loading initial ramdisk...`). Se realizó una **reinstalación limpia de Proxmox VE** (usando `chroot` desde un Ubuntu Live USB) tras fallar los intentos de reparación (`update-initramfs`, `proxmox-boot-tool`).
- **Corrección de Red (Host):** Se eliminó un conflicto de IP que hacía que DHCP sobreescribiera la configuración, definiendo una **IP estática** para `vmbr0` en `/etc/network/interfaces`.
- **Corrección de PATH en Cron:** Se solucionó el fallo de scripts en `cron` (comandos como `pct` o `ionice` no encontrados) añadiendo una variable `PATH` global al crontab (`PATH=/usr/local/sbin:/usr/local/bin...`).
- **Corrección de Puntos de Montaje LXC:** Se resolvió el error crítico `lxc.hook.pre-start` que impedía que los contenedores arrancaran:
  - Se eliminaron los “montajes fantasma” (`mpX`) usando `pct set <vmid> --delete mpX`.
  - Se corrigió `/etc/fstab` para lograr montajes **NTFS** estables usando `ntfs-3g` y `rw,allow_other`.

### 🛡️ Scripts de Resiliencia (Nuevas Capacidades)

Se crearon y refactorizaron tres scripts a nivel **production-grade**  
`sync_lxc_backups.sh`, `backup_host.sh`, `check_disk.sh`:

- **Logging Persistente:** Todos los scripts ahora escriben en archivos de log dedicados (por ejemplo, `/mnt/disco8tb/logs/`) mediante un helper `log()` que usa `tee -a $LOG_FILE`.
- **Bloqueo de Concurrencia (`flock`):** Evita que se solapen ejecuciones de `cron` (`exec 9>/var/lock/script.lock`).
- **Captura de Errores (`trap`):** Se añadieron `trap _on_error ERR` y `trap _on_term INT TERM` para capturar fallos inesperados, registrarlos y enviar una alerta de “fallo” a n8n.
- **Chequeos Pre-vuelo:** Los scripts verifican binarios requeridos (`rclone`, `zstd`, `pct`) y directorios con permisos de escritura antes de iniciar.
- **Modo Prueba (`DRYRUN`):** Se añadió `DRYRUN=1` para simular operaciones de forma segura (por ejemplo, `rclone --dry-run`).
- **Payloads JSON Endurecidos:** Se implementó `json_escape` para garantizar que los mensajes de error se envíen en JSON válido.
- **Optimización en Cron:** Se añadió `ionice -c 3` y `nice -n 19` a la tarea de sincronización de backups para minimizar el impacto en el host.

### 💾 Mejoras en la Lógica de Backups (`sync_lxc_backups.sh` v4.7)

El motor de backups de LXC ahora incluye mecanismos robustos de protección:

- **Verificación Estricta en 5 Pasos:**
  1. `wait_stable_size` — Asegura que el tamaño del archivo deje de cambiar antes de procesarlo.
  2. Verificación de existencia del archivo `.log`.
  3. `grep -qi "ERROR:"` — Verifica que el log no contenga errores.
  4. `grep -Eqi "INFO:.*finished"` — Confirma que el backup terminó correctamente.
  5. `zstd -t -T0` — Prueba de integridad multi-hilo.
- **Lógica de Staging:** Los backups válidos se copian a `cloud_staging/`.  
  El script **nunca borra la última copia conocida como buena** si el backup del día falla.
- **Gestión de Cuota:** Usa `--drive-use-trash=false` para borrar permanentemente archivos antiguos en la nube y evitar llenar la papelera de Google Drive.
- **Auto-creación de Remote:** Ejecuta automáticamente `rclone mkdir` si la carpeta de Google Drive no existe.

### 📡 Alertas y Monitoreo (n8n)

Se implementó un sistema completo de monitoreo en n8n:

- **Workflows Estandarizados:** Se crearon tres workflows:
  - `lxc_backup_alerts`
  - `host_backup_alert`
  - `disk_alert`
- **Lógica `IF` Correcta:** `fail_count` se evalúa correctamente como **Número**, asegurando la rama adecuada entre “Éxito Total” y “Éxito con Fallos”.
- **Corrección de Formato en Telegram:** Se solucionó el error `400 Bad Request: can't parse entities`:
  1. Se cambió el Parse Mode a **HTML**
  2. Se usó `<b>` para negritas
  3. Se envolvieron las listas de errores en `<pre>...</pre>` para evitar que Telegram interprete Markdown.

### 🧑‍💻 Entorno de Desarrollo

- **IDE Centralizado:** Se instaló y configuró **`code-server`** (VS Code en el navegador) en un LXC dedicado.
- **Acceso Seguro:** Expuesto mediante **Nginx Proxy Manager** con subdominio, SSL (Let’s Encrypt) y soporte de WebSockets.

### 📂 Mejora en la Gestión del Proyecto (GitHub)

Se crearon dos repositorios de GitHub para estandarizar la estructura del proyecto:

#### `Resilient_Proxmox_ReProxm`

- Se subieron versiones anonimizadas de los 3 scripts Bash (v4.x / v2.x)
- Se subieron los 3 workflows de n8n (`.json`)
- Se añadió un `install.sh` robusto (copia, reemplazo de placeholders, crontab)
- Se crearon `README.md` (inglés) y `README-es.md` (español) detallados
- Se añadieron `ISSUE_TEMPLATE`s bilingües para bugs y mejoras

#### `gh-issue-importer`

- Se creó una herramienta en PowerShell + `gh` CLI para importar issues desde un archivo JSON  
  (sustituyendo importaciones frágiles vía CSV)
- Incluye un guardrail que crea etiquetas faltantes automáticamente
- Se importó un backlog de ~40 issues bilingües
