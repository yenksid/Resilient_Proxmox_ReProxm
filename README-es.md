[UPDATED DOCUMENT]
[UPDATED DOCUMENT]
# Resilient Proxmox: For Unstable Micro-Servers

> Automated disaster recovery for microservers that need to recover themselves

[![Proxmox](https://img.shields.io/badge/Proxmox-E97B00?style=flat-square&logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Bash](https://img.shields.io/badge/GNU%20Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![n8n](https://img.shields.io/badge/n8n-1A1A1A?style=flat-square&logo=n8n&logoColor=white)](https://n8n.io/)
[![rclone](https://img.shields.io/badge/rclone-0078D4?style=flat-square&logo=rclone&logoColor=white)](https://rclone.org/)

**English** | [**Español**](README-es.md) | [**Changelog**](CHANGELOG.md)

## 📑 Table of Contents

- [Why This Project?](#-why-this-project)
- [What Does This Kit Solve?](#-what-does-this-kit-solve)
- [Guía de instalación rápida](#-guía-de-instalación-rápida)
- [The Journey: Disaster Recovery Guide](#-the-journey-a-disaster-recovery-guide)
- [The Automation Kit](#-the-automation-kit--how-it-works)
- [Release Notes](#-release-notes)

## ❓ Why This Project?

¿Alguna vez has reiniciado tu servidor Proxmox o se ha quedado sin energía y, al volver, solo la mitad de tus servicios han levantado? ¿O quizá estás haciendo una instalación limpia de Proxmox y quieres restaurar tus backups de contenedores manteniéndolos configurados, actualizados y seguros?

Si es así, este kit es para ti.

## 🚀 What Does This Kit Solve?

Este repositorio es una colección de guías y scripts nacidos de un caso real de recuperación ante desastres. Su objetivo es hacer que tu servidor Proxmox sea resiliente (capaz de recuperarse por sí mismo) automatizando las tareas críticas que suelen fallar en los microservidores:

- **Automated backups**
  - Realiza backups del **Host** (configuración de Proxmox en `/etc`) y de tus **LXC** (datos) hacia la nube (por ejemplo, Google Drive)

- **Integrity verification**
  - Detecta archivos corruptos con `zstd -t` antes de subirlos
  - Lee los archivos `.log` para identificar fallos en la creación del backup

- **Safe retention management**
  - Usa una carpeta intermedia de *staging*
  - Garantiza que tu último backup válido en la nube **nunca se borre**, incluso si el backup diario falla

- **Google Drive quota management**
  - Vacía automáticamente la papelera con `rclone cleanup`
  - Protege tu límite gratuito de 15 GB

- **Real-time alerting**
  - Envía notificaciones a Telegram mediante n8n
  - Reporta éxitos, corrupciones y errores de subida

- **Post-rebuild guidance**
  - Soluciones para errores `lxc.hook.pre-start`
  - Guía para depurar problemas de permisos en discos NTFS

## 🚀 Guía de instalación rápida

Esta sección es para quienes desean poner el kit en funcionamiento sin leer toda la explicación completa. Se asume que ya tienes un servidor Proxmox VE funcionando correctamente.

### Requisitos previos

Asegúrate de contar con lo siguiente:

✅ Un servidor Proxmox VE en ejecución con acceso `root` (o `sudo`)  
✅ Tu(s) disco(s) externo(s) de backup montado(s) (por ejemplo, en `/mnt/disco8tb`)  
✅ Una instancia de [n8n](https://n8n.io/) (autoalojada o en la nube)  
✅ Una cuenta de Google Drive  
✅ Un `Token` de bot de Telegram y tu `Chat ID`

### Paso 1: Instalar dependencias (en el host Proxmox)

Inicia sesión en la shell de Proxmox por SSH e instala `rclone` (para la sincronización en la nube) y `zstd` (para las comprobaciones de integridad):

```bash
sudo apt update
sudo apt install rclone zstd -y
```

### Paso 2: Configurar rclone

Autoriza a rclone a acceder a tu Google Drive.

Ejecuta el asistente de configuración:

```bash
rclone config

Sigue estos pasos interactivos:

1. `n` → Nuevo remoto
2. `name` → `gdrive` ← Este nombre exacto es obligatorio; los scripts lo usan
3. `Storage` → `drive` (Google Drive)
4. `client_id` y `client_secret` → Déjalos en blanco (pulsa Enter)
5. `scope` → `1` (acceso completo)
6. `root_folder_id` → Opcional (pega el ID de tu carpeta de backups en Drive)
7. `service_account_file` → Déjalo en blanco (pulsa Enter)
8. `Edit advanced config?` → `n`
9. `Use auto config?` → `n` (crucial para servidores sin interfaz gráfica)
10. rclone mostrará una URL `https://accounts.google.com/...`
    - Cópiala y ábrela en el navegador de tu PC
    - Autoriza con la cuenta de Google correcta (la que tiene 15 GB libres)
    - Copia el código de verificación que te da Google y pégalo de nuevo en la terminal de Proxmox
11. `Configure as team drive?` → `n`
12. `y` (Sí, esto está bien)
13. `q` (Salir)

### Paso 3: Configurar los workflows de n8n

En tu instancia de n8n, importa los tres workflows desde el directorio `/n8n_workflows`:

- `lxc_backup_alerts.json`
- `host_backup_alert.json`
- `disk_alert.json`

Para cada workflow:

- Actualiza el nodo de Telegram con tu Chat ID
- Copia la URL de Producción desde el nodo Webhook
- Activa el workflow (cambia el interruptor a verde)

> 💡 **Nota**: Usa la IP interna de tu instancia de n8n en la URL del webhook (por ejemplo, `http://10.0.0.62:5678/webhook/...`), no un dominio externo. Esto evita errores de NAT loopback cuando Proxmox envía alertas.

### Paso 4: Copiar y configurar los scripts

1. Clona este repositorio en tu host Proxmox:
   ```bash
   git clone [YOUR_REPO_URL_HERE]
   cd [YOUR_REPO_NAME]
   ```

2. Copia los scripts a `/root/`:
   ```bash
   sudo cp ./scripts/*.sh /root/
   ```

3. Hazlos ejecutables:
   ```bash
   sudo chmod +x /root/*.sh
   ```

4. Edita los scripts para que se adapten a tu entorno:

#### `sync_lxc_backups.sh`

```bash
sudo nano /root/sync_lxc_backups.sh
```

Variables a configurar:
- `LOCAL_DUMP_FOLDER`: Ruta a tus dumps (por ejemplo, `/mnt/disco8tb/dump`)
- `LOCAL_STAGING_FOLDER`: Ruta de staging (por ejemplo, `/mnt/disco8tb/cloud_staging`)
- `REMOTE_FOLDER`: remoto de rclone (por ejemplo, `gdrive:LXC_Backups`)
- `N8N_WEBHOOK_URL`: URL del workflow `lxc_backup_alerts.json`

#### `backup_host.sh`

```bash
sudo nano /root/backup_host.sh
```

Variables a configurar:
- `DEST_DIR`: Destino del backup del host (por ejemplo, `/mnt/disco8tb/host_backup`)
- `N8N_WEBHOOK_URL`: URL del workflow `host_backup_alert.json`

#### `check_disk.sh`

```bash
sudo nano /root/check_disk.sh
```

Variables a configurar:
- `N8N_WEBHOOK_URL`: URL del workflow `disk_alert.json`
- `DISK_PATH`: Disco a monitorear (por ejemplo, `/mnt/disco8tb`)
- `THRESHOLD`: Porcentaje de alerta (por ejemplo, `90`)

### Paso 5: Programar con crontab

1. Abre el crontab del usuario root:
   ```bash
   sudo crontab -e
   ```

2. Pega esta programación escalonada al final (para ejecución nocturna):
   ```bash
   # Suponiendo que tu tarea principal de backup LXC en Proxmox corre a las 3:00 AM
   
   # 4:00 AM: Backup de la configuración del host Proxmox
   0 4 * * * /root/backup_host.sh >/dev/null 2>&1
   
   # 4:30 AM: Sincronizar los backups LXC a la nube
   30 4 * * * /root/sync_lxc_backups.sh >/dev/null 2>&1
   
   # 5:00 AM: Actualización automática de paquetes (opcional pero recomendada)
   0 5 * * * apt-get update && apt-get upgrade -y >/dev/null 2>&1
   
   # 6:00 AM: Comprobar uso de disco
   0 6 * * * /root/check_disk.sh >/dev/null 2>&1
   ```

3. Guarda y sal del editor.

✨ **Listo.** Tu servidor ahora está automatizado y es resiliente.

> **Nota (cron + ionice/nice):** Si usas una línea más agresiva para la sincronización de backups LXC como:
>
> ```bash
> # 4:30 AM: Sync LXC backups to the cloud with low I/O/CPU priority
> 30 4 * * * ionice -c 3 nice -n 19 /root/sync_lxc_backups.sh >/dev/null 2>&1
> ```
>
> y el script **no** se ejecuta, la causa más frecuente es que `cron` no puede encontrar los binarios `ionice` y/o `nice` por tener un `PATH` restringido.
>
> Una solución profesional y robusta es definir un PATH completo al inicio del crontab de root:
>
> ```bash
> PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
> ```
>
> Esto garantiza que `cron` pueda localizar `ionice`, `nice` y otros comandos del sistema, de modo que `/root/sync_lxc_backups.sh` se ejecute de forma fiable incluso cuando se envuelve con `ionice`/`nice`.

---

## 🔥 The Journey: A Disaster Recovery Guide

> La Guía de instalación rápida es para cuando todo funciona. Esta guía es para cuando todo se rompe.  
> Es un registro real de lo que falló, lo que probamos y lo que finalmente funcionó.

### Part 1: The Server Died (Diagnosis)

Este kit existe porque el host dejó de arrancar después de un reinicio. Si estás aquí, probablemente estés en la misma situación.

#### Symptom

El servidor se queda detenido en:
```
Loading initial ramdisk...```
(justo después del menú de GRUB)

#### What We Tried First

- Arrancar Proxmox en "Recovery Mode" desde "Advanced options"
  - Resultado: también falló

#### Diagnosis

Si tanto el kernel principal como el de recuperación fallan, el gestor de arranque o el initrd (initial ramdisk) está críticamente dañado. Intentamos la recuperación iniciando desde un USB de Ubuntu Live y usando `chroot` sobre la instalación de Proxmox para repararla.

#### Attempts (That Failed)

```bash
# Rebuild all initramfs images
update-initramfs -u -k all

# Regenerate GRUB config
update-grub

# Re-initialize Proxmox boot partition (example device)
proxmox-boot-tool init /dev/sdX#
```

#### Decision

Cuando las reparaciones basadas en `chroot` también fallan, acabarás invirtiendo más tiempo intentando resucitar un sistema roto que reinstalándolo desde cero. Declaramos el sistema operativo del host como perdido y procedimos con una reinstalación limpia de Proxmox.

### Part 2: The Rebuild (Essential Post-Install Fixes)

Después de reinstalar Proxmox, los backups de LXC se restauran correctamente, pero el host aún no es estable. Aplica primero estas correcciones manuales.

#### 1️⃣ Network — Set a Static IP

Tu host necesita una dirección fiable. No dependas solo de reservas por DHCP: configúrala directamente en el host.

1. Inicia sesión en la shell de Proxmox (root@pmox) y edita:
   ```bash
   sudo nano /etc/network/interfaces
   ```

2. Localiza `vmbr0` y cámbialo de dhcp a static (usando tus propias direcciones):
   ```bash
   auto vmbr0
   iface vmbr0 inet static
       address <your_proxmox_ip>/24
       gateway <your_gateway_ip>
       bridge-ports <your_interface_name>
       bridge-stp off
       bridge-fd 0
   ```

3. Añade DNS para que el host pueda salir a internet y obtener actualizaciones:
   ```bash
   sudo nano /etc/resolv.conf
   
   nameserver 8.8.8.8
   nameserver 1.1.1.1
   ```

#### 2️⃣ SSH — "Host Identification Has Changed"

Tras una reinstalación limpia, es muy probable que tu primer intento de conexión por SSH sea bloqueado:

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
...
Host key verification failed.```

Esto es normal: tu PC tiene en caché la clave antigua del host. El servidor recién reinstalado tiene una nueva huella.

1. Solución (en tu PC local):
   ```bash
   ssh-keygen -R <your_proxmox_ip>
   ```

2. Luego intenta de nuevo:
   ```bash
   ssh root@<your_proxmox_ip>
   ```

3. Acepta la nueva clave cuando se te pregunte (`yes`)

#### 3️⃣ Security — Harden SSH (Disable root login)

Este es el paso de endurecimiento básico más importante.

1. Crea un usuario administrador en el host:
   ```bash
   adduser <your_admin_user>
   ```

2. Concede permisos sudo:
   ```bash
   usermod -aG sudo <your_admin_user>
   ```

3. Haz una prueba en una segunda terminal:
   ```bash
   ssh <your_admin_user>@<your_proxmox_ip>
   sudo whoami   # debería mostrar "root"
   ```

4. Solo si la prueba funciona, deshabilita el login directo de root en tu primera terminal:
   ```bash
   sudo nano /etc/ssh/sshd_config
   ```

5. Busca (o añade) y establece:
   ```bash
   PermitRootLogin no
   ```

6. Reinicia SSH:
   ```bash
   sudo systemctl restart sshd
   ```

7. A partir de ahora, inicia sesión como `<your_admin_user>` y usa `sudo` para las tareas de administración

### Part 3: The LXC Headache (Fixing Mount-Point Errors)

Después de una reinstalación limpia, los problemas más molestos suelen ser los fallos al iniciar contenedores LXC. Restauras desde un backup, haces clic en "Start" y el contenedor se cae con un error genérico.

#### Typical startup log:

```
lxc.hook.pre-start: ... failed to run
__lxc_start: ... failed to initialize
startup for container '10X' failed
```

En casi todos los casos, esto apunta a un punto de montaje de almacenamiento que está fallando. Hemos visto dos causas principales.

#### Cause 1️⃣ — "Ghost" Mount Points

Los backups preservan no solo los datos, sino también la configuración del contenedor (por ejemplo, `101.conf`), que incluye referencias a montajes de discos antiguos.

**Problem**

Tu nuevo host puede usar rutas diferentes (por ejemplo, `/mnt/disco8tb`) o puedes tener entradas `mpX` obsoletas que ya no existen. LXC intenta montar esas rutas y falla.

1. Inspecciona la configuración (sustituye 101 por el ID de tu CT):
   ```bash
   cat /etc/pve/lxc/101.conf
   ```

2. Verás algo como:
   ```bash
   # OK: root disk on storage
   rootfs: DataStore01:101/vm-101-disk-1.raw,size=8G

   # BAD: stale mounts from the old host
   mp0: /mnt/backup8tb/media,mp=/media
   mp1: /mnt/disco8tb,mp=/media/storage
   ```

3. Solución (eliminar montajes fantasma):
   ```bash
   pct set 101 --delete mp0
   pct set 101 --delete mp1
   ```

4. Intenta iniciar de nuevo el contenedor. Si arranca, vuelve a añadir los puntos de montaje correctos desde la GUI de Proxmox (Hardware → Add → Mount Point)

#### Cause 2️⃣ — The NTFS Filesystem Trap

Si tus discos externos (por ejemplo, ese disco de 8 TB) están formateados en NTFS por compatibilidad con Windows, es muy probable que te encuentres con problemas de mapeo de permisos.

**Problem**

Linux puede leer NTFS, pero su modelo de permisos no se mapea bien a LXC. Incluso los contenedores privilegiados pueden fallar en el hook de prearranque cuando el montaje en el host no expone propietarios/permisos de forma utilizable.

**Solución — montar NTFS con opciones permisivas en el host**

1. Instala el driver adecuado:
   ```bash
   sudo apt install ntfs-3g -y
   ```

2. Localiza el UUID de tu disco:
   ```bash
   sudo blkid
   ```
   Example output snippet:
   ```
   # /dev/sdb2: UUID="1A04B4DE04B4BE57" TYPE="ntfs" ...
   ```

3. Crea el punto de montaje (si hace falta) y hazlo persistente en `fstab`:
   ```bash
   sudo mkdir -p /mnt/disco8tb
   sudo nano /etc/fstab
   ```

4. Añade la línea (sustituye con tu UUID y ruta de montaje):
   ```bash
   # Format: UUID=[your_uuid]  [mount_path]   [filesystem]  [options]          0 0
   UUID=1A04B4DE04B4BE57  /mnt/disco8tb  ntfs-3g  rw,allow_other  0  0
   ```
   - `ntfs-3g`: reliable NTFS driver
   - `rw,allow_other`: exposes the mount broadly so LXC can access it

5. Aplica y verifica:
   ```bash
   sudo mount -a
   mount | grep /mnt/disco8tb
   ```

Con el montaje NTFS del host configurado de esta manera, tus contenedores LXC deberían arrancar sin problemas.

---

## 🤖 The Automation Kit — How It Works

Esto no son "solo scripts". Es una tubería resiliente que valida backups, mantiene copias conocidas como buenas, sincroniza con la nube, limpia lo que sobra y envía alertas, para que puedas confiar en ella y depurar problemas con confianza.

### 1️⃣ sync_lxc_backups.sh — Core Logic

Está diseñado para evitar subidas corruptas y pérdidas de datos accidentales. Hace mucho más que simplemente copiar archivos.

#### 🛡️ Staging (safety net)

Crea una carpeta `cloud_staging/` que debe contener siempre el último backup válido por LXC. Si el backup de hoy del LXC-101 está corrupto, la copia buena de ayer permanece en staging.

**Resultado**: nunca sincronizas un backup corrupto ni borras tu última copia válida.

#### ✅ Verification (two checks before staging)

- **Log check**: revisa el `.log` más reciente buscando `ERROR:` (ignorando mayúsculas/minúsculas) para detectar fallos en la creación del backup
- **Success check**: requiere una marca de éxito (por ejemplo, `INFO: backup finished`) en el `.log`
- **Integrity check**: ejecuta `zstd -t -T0` sobre el `.tar.zst` más reciente para asegurarse de que se puede descomprimir
- **Stability check**: `wait_stable_size` se asegura de que el archivo no se esté escribiendo todavía

#### 🔔 Alerting (fail fast, skip safely)

Si alguna comprobación falla, el script envía una alerta detallada a n8n y se salta ese contenedor. La carpeta de staging conserva el backup válido anterior.

#### 🔄 Cloud sync (incremental & fast)

Usa `rclone sync` para reflejar `cloud_staging/` en Google Drive: solo se transfieren los archivos nuevos o modificados.

#### 🗑️ Trash cleanup (quota-friendly)

Ejecuta `rclone sync ... --drive-use-trash=false` para borrar definitivamente archivos antiguos, protegiendo tus 15 GB de cuota gratuita (sin pasar por la papelera).

#### ✅ Guarantees

- Nunca sobrescribe tu último backup válido con uno corrupto
- Ejecuciones diarias idempotentes (seguro de volver a ejecutarlo)
- Señales claras cuando algo va mal

### 2️⃣ backup_host.sh & check_disk.sh — Essential Helpers

#### backup_host.sh

Crea un snapshot `.tar.gz` de `/etc` y `/root`, capturando la configuración de red, `fstab`, `sshd_config` y estos scripts. Es el "cerebro" de tu host en un solo archivo.

#### check_disk.sh

Comprueba el uso de disco con `df`. Si el uso supera `THRESHOLD` (por ejemplo, 90%), envía una alerta concisa a n8n para que puedas resolver la presión de almacenamiento antes de que empiecen a fallar los backups.

### 3️⃣ n8n Alerting Workflows — Smart, Readable Notifications

Los scripts hacen un POST de JSON a webhooks de n8n; n8n transforma esa información en mensajes claros de Telegram.

#### IF logic (in lxc_backup_alerts.json)

Ejemplo de payload:

```json
{
  "status": "exito",
  "success_count": 12,
  "fail_count": 1,
  "fail_reasons": "LXC-107: zstd integrity check failed"
}
```

El nodo IF evalúa: ¿es `fail_count` (como Número) mayor que 0?

- **True**: envía "Success with Failures" (incluye las razones)
- **False**: envía "Total Success"

#### Corrigiendo los problemas de formato de Telegram

**Error que verás si no usas nuestras plantillas:**

```
Bad Request: can't parse entities: Character '_' is reserved
```

**Por qué**: el parser de Markdown de Telegram interpreta `_` / `-` en los nombres de archivo (por ejemplo, `vzdump-lxc-107...`) como formato.

**Solución (aplicada en todos los nodos de Telegram):**

- Parse Mode: ponlo en **HTML** (más predecible que Markdown)
- Usa `<b>` para negritas en lugar de `*text*`
- Envuelve listas de errores/nombres de archivo en `<pre>...</pre>` para que Telegram no los intente parsear:

```html
<b>Status:</b> {{ $json.body.status }}<br/>
<b>Succeeded:</b> {{ $json.body.success_count }}<br/>
<b>Failed:</b> {{ $json.body.fail_count }}<br/>
<b>Reasons:</b>
<pre>{{ $json.body.fail_reasons }}</pre>
```

---

## 📜 Release Notes

> Este proyecto sigue las convenciones de **Keep a Changelog** y **Semantic Versioning**.  
> Todo el historial de versiones detallado se mantiene en [`CHANGELOG.md`](CHANGELOG.md).

### 🏷️ Versioning Scheme

Las versiones siguen el formato **MAJOR.MINOR.PATCH**:

- **MAJOR** — Cambios rompientes o actualizaciones de arquitectura incompatibles  
- **MINOR** — Nuevas funcionalidades retrocompatibles  
- **PATCH** — Correcciones de errores y pequeñas mejoras  

### 📦 Release Template (para nuevas versiones)

Cuando publiques una nueva versión, añade una entrada en `CHANGELOG.md` usando esta estructura:

    ## [vX.Y.Z] — YYYY-MM-DD

    ### 🚀 New Features
    - ...

    ### 🔧 Enhancements
    - ...

    ### 🐛 Bug Fixes
    - ...

    ### ⚠️ Breaking Changes
    - ...

    ### 🔄 Migration Notes
    - ...

    ### 🧠 Technical Notes
    - ...

Para el historial detallado de `ReProxm v1.0 ("Resilience")`, consulta la entrada dedicada en [`CHANGELOG.md`](CHANGELOG.md).

## 📝 License

Este proyecto se distribuye bajo la licencia MIT. Consulta [LICENSE](LICENSE) para más detalles.

## 🤝 Contributing

Las contribuciones son bienvenidas. Siéntete libre de abrir *issues* o enviar *pull requests*.

## 📧 Support

Para preguntas, problemas o sugerencias, abre un *issue* en este repositorio.
