# Proxmox resiliente: para microservidores inestables

> Automatización de recuperación ante desastres para microservidores que deben poder recuperarse por sí mismos.

[![Proxmox](https://img.shields.io/badge/Proxmox-E97B00?style=flat-square&logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Bash](https://img.shields.io/badge/GNU%20Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![n8n](https://img.shields.io/badge/n8n-1A1A1A?style=flat-square&logo=n8n&logoColor=white)](https://n8n.io/)
[![rclone](https://img.shields.io/badge/rclone-0078D4?style=flat-square&logo=rclone&logoColor=white)](https://rclone.org/)

**Español** | [**English**](README.md)

## 📑 Índice

- [¿Qué resuelve este kit?](#que-resuelve)
- [Guía rápida de instalación](#guia-rapida)
- [La travesía: guía de recuperación](#la-travesia)
- [El kit de automatización (cómo funciona)](#kit-automatizacion)

---

<a id="que-resuelve"></a>
## 🚀 ¿Qué resuelve este kit?

Este repositorio reúne guías y scripts nacidos de una recuperación de desastres real. Su objetivo es volver tu Proxmox resiliente (capaz de recuperarse por sí mismo) automatizando tareas críticas que suelen fallar en microservidores:

- Automatiza copias de seguridad del **Host** (configuración de Proxmox en `/etc`) y de los **LXC** (datos) hacia la nube (p. ej., Google Drive).
- Verifica la integridad antes de subir (p. ej. `zstd -t`) y detecta fallos leyendo los `.log`.
- Gestiona la retención con una carpeta de "staging" para no perder la última copia válida.
- Administra la cuota de Google Drive limpiando la papelera con `rclone cleanup`.
- Envía alertas en tiempo real a Telegram a través de n8n (éxitos, corrupciones, errores).
- Incluye guía de posreconstrucción para problemas como `lxc.hook.pre-start` y permisos NTFS.

---

## 🚀 Guía rápida de instalación

Esta sección es para quien quiera poner el kit en marcha sin leer todo el trasfondo. Asume que ya tienes un Proxmox VE funcionando.

### Requisitos previos

- Un servidor Proxmox VE en ejecución, con acceso `root` o `sudo`.
- Disco(s) externo(s) de backup montado(s) (p. ej., `/mnt/disco8tb`).
- Una instancia de [n8n](https://n8n.io/).
- Una cuenta de Google Drive.
- Un Bot Token de Telegram y tu `Chat ID`.

### Paso 1: Instalar dependencias (en el host Proxmox)

```bash
sudo apt update
sudo apt install rclone zstd -y
```

<a id="guia-rapida"></a>
### Paso 2: Configurar rclone

```bash
rclone config
```

Sigue los pasos interactivos:

1. `n` → New remote
2. `name` → `gdrive` (los scripts lo esperan con este nombre)
3. `Storage` → `drive` (Google Drive)
4. `client_id` y `client_secret` → dejar en blanco
5. `scope` → `1` (Full access)
6. `root_folder_id` → opcional
7. `service_account_file` → dejar en blanco
8. `Edit advanced config?` → `n`
9. `Use auto config?` → `n` (importante para servidores sin GUI)
10. Sigue la URL que muestra rclone desde un navegador y pega el código de verificación en la terminal.
11. `Configure as team drive?` → `n`
12. `y` (Yes) → `q` (Quit)

### Paso 3: Preparar los flujos en n8n

Importa al menos estos workflows desde la carpeta `/n8n_workflows`:

- `lxc_backup_alerts.json`
- `host_backup_alert.json`
- `disk_alert.json`

Para cada workflow:

- Actualiza el nodo de Telegram con tu Chat ID.
- Copia la Production URL del nodo Webhook.
- Activa el workflow.

> Nota: Usa la IP interna de n8n en el webhook (ej. `http://10.0.0.62:5678/webhook/...`) para evitar problemas de NAT loopback.

### Paso 4: Copiar y configurar los scripts

```bash
git clone [URL_DE_TU_REPO]
cd [NOMBRE_DEL_REPO]
sudo cp ./scripts/*.sh /root/
sudo chmod +x /root/*.sh
```

Edita las variables dentro de los scripts (`/root/sync_lxc_backups.sh`, `/root/backup_host.sh`, `/root/check_disk.sh`) para adaptarlas a tu entorno:

- `LOCAL_DUMP_FOLDER`, `LOCAL_STAGING_FOLDER`, `REMOTE_FOLDER`, `N8N_WEBHOOK_URL` (en `sync_lxc_backups.sh`)
- `DEST_DIR`, `N8N_WEBHOOK_URL` (en `backup_host.sh`)
- `N8N_WEBHOOK_URL`, `DISK_PATH`, `THRESHOLD` (en `check_disk.sh`)

### Paso 5: Programar con crontab

Edita el crontab de root:

```bash
sudo crontab -e
```

Pega una programación segura y escalonada (ejecución nocturna):

```bash
# 4:00 AM: Backup de la configuración del host Proxmox
0 4 * * * /root/backup_host.sh >/dev/null 2>&1

# 4:30 AM: Verificar y sincronizar backups LXC a la nube
30 4 * * * ionice -c 3 nice -n 19 /root/sync_lxc_backups.sh >/dev/null 2>&1

# 5:00 AM: Actualización automática del host (opcional)
0 5 * * * apt update && apt dist-upgrade -y >/dev/null 2>&1

# 6:00 AM: Comprobar espacio libre del disco principal
0 6 * * * /root/check_disk.sh >/dev/null 2>&1
```

¡Listo! Tu servidor queda automatizado y resiliente.

---

<a id="la-travesia"></a>
## 🔥 La travesía: guía de recuperación de desastres

Esta guía es una bitácora: lo que falló, lo que intentamos y lo que finalmente funcionó.

### Parte 1: El servidor murió (diagnóstico)

**Síntoma**

El servidor se congela en:

```
Loading initial ramdisk...
```

Intentamos arrancar en "Recovery Mode" sin éxito.

**Diagnóstico**

Si kernel y recovery fallan, el bootloader o el initrd están corruptos. Intentamos chroot desde un Live USB para reparar.

**Comandos intentados:**

```bash
# Rebuild initramfs
update-initramfs -u -k all

# Regenerate GRUB
update-grub

# Re-init Proxmox boot (ejemplo)
proxmox-boot-tool init /dev/sdX#
```

Si estas reparaciones fallan, una reinstalación limpia puede ser más rápida.

### Parte 2: La reconstrucción (arreglos post-instalación)

#### 1️⃣ Red — IP estática

Edita `/etc/network/interfaces` en el host Proxmox y configura `vmbr0` como estática. Ejemplo:

```bash
sudo nano /etc/network/interfaces

auto vmbr0
iface vmbr0 inet static
		address <tu_ip_proxmox>/24
		gateway <tu_ip_gateway>
		bridge-ports <tu_interfaz_red>
		bridge-stp off
		bridge-fd 0
```

Añade DNS en `/etc/resolv.conf`:

```bash
sudo nano /etc/resolv.conf
```

Ejemplo:

```text
nameserver 8.8.8.8
nameserver 1.1.1.1
```

#### 2️⃣ SSH — "Host Identification Has Changed"

Tras una reinstalación, tu PC puede bloquear la conexión SSH por una huella cambiada. En tu PC local elimina la entrada antigua:

```bash
ssh-keygen -R <tu_ip_proxmox>
ssh root@<tu_ip_proxmox>
```

Acepta la nueva huella (`yes`) cuando se te solicite.

#### 3️⃣ Seguridad — Desactivar login directo de root

1. Crea un usuario admin y añade a sudoers:

```bash
adduser <tu_usuario_admin>
usermod -aG sudo <tu_usuario_admin>
```

2. Prueba en otra terminal que `sudo` funciona:

```bash
ssh <tu_usuario_admin>@<tu_ip_proxmox>
sudo whoami  # debe devolver "root"
```

3. Si todo está bien, edita `/etc/ssh/sshd_config` y desactiva el login de root:

```bash
sudo nano /etc/ssh/sshd_config
# set: PermitRootLogin no
sudo systemctl restart sshd
```

### Parte 3: El dolor de cabeza de LXC (mount points)

Los errores `lxc.hook.pre-start` o fallos al arrancar contenedores tras restaurar backups suelen indicar problemas en los puntos de montaje.

#### Causa 1 — Mount points "fantasma"

Los archivos de configuración de LXC (ej. `/etc/pve/lxc/101.conf`) pueden contener referencias a mount points del host antiguo que ya no existen.

Inspecciona el config:

```bash
cat /etc/pve/lxc/101.conf
```

Si ves entradas `mp0`, `mp1` que apuntan a rutas inexistentes, elimínalas:

```bash
pct set 101 --delete mp0
pct set 101 --delete mp1
```

Después intenta arrancar el contenedor nuevamente.

#### Causa 2 — La trampa NTFS

Si tus discos externos están en NTFS, el modelado de permisos puede producir fallos en LXC. Monta NTFS con `ntfs-3g` y opciones permisivas:

```bash
sudo apt install ntfs-3g -y
sudo blkid
sudo mkdir -p /mnt/disco8tb
sudo nano /etc/fstab
# Añade: UUID=XXXXXXXX  /mnt/disco8tb  ntfs-3g  rw,allow_other  0 0
sudo mount -a
mount | grep /mnt/disco8tb
```

---

<a id="kit-automatizacion"></a>
## 🤖 El kit de automatización (cómo funciona)

Este conjunto de scripts implementa una tubería resiliente:

- Staging: mantiene la última copia válida por LXC en `cloud_staging/`.
- Verificación: comprobaciones en logs, marca de éxito, integridad (`zstd -t`) y estabilidad del archivo.
- Alertas: envía detalles a n8n en caso de errores y omite contenedores con fallos.
- Sync: `rclone sync` desde `cloud_staging/` a `gdrive:`.
- Limpieza: usa `--drive-use-trash=false` para ahorrar cuota.

### 1️⃣ `sync_lxc_backups.sh` — Lógica central

- Crea y mantiene `cloud_staging/` con la última copia válida por LXC.
- Verifica con logs y `zstd -t` antes de mover a staging.
- Envía alertas a n8n en caso de errores; no sobrescribe la última copia válida.

### 2️⃣ `backup_host.sh` y `check_disk.sh`

- `backup_host.sh`: snapshot de `/etc` y `/root`.
- `check_disk.sh`: revisa `df` y alerta si se supera `THRESHOLD`.

### 3️⃣ n8n — Workflows y formato para Telegram

Los scripts POST JSON a n8n; n8n transforma el payload en mensajes Telegram con Parse Mode = HTML. Encierra listas/errores en `<pre>...</pre>`.

Ejemplo de payload:

```json
{
	"status": "exito",
	"success_count": 12,
	"fail_count": 1,
	"fail_reasons": "LXC-107: zstd integrity check failed"
}
```

Plantilla HTML recomendada en n8n:

```html
<b>Estado:</b> {{ $json.body.status }}<br/>
<b>Exitosos:</b> {{ $json.body.success_count }}<br/>
<b>Fallidos:</b> {{ $json.body.fail_count }}<br/>
<b>Razones:</b>
<pre>{{ $json.body.fail_reasons }}</pre>
```

---

## 📝 Licencia

MIT. Ver [LICENSE](LICENSE).

## 🤝 Contribuciones

Pull requests y issues son bienvenidos.

## 📧 Soporte

Abre una issue en este repositorio para preguntas o feedback.