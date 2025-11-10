# Proxmox Resiliente (ReProxm)

> Para microservidores inestables que necesitan recuperarse automáticamente

[![Proxmox](https://img.shields.io/badge/Proxmox-E97B00?style=flat-square&logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Bash](https://img.shields.io/badge/GNU%20Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![n8n](https://img.shields.io/badge/n8n-1A1A1A?style=flat-square&logo=n8n&logoColor=white)](https://n8n.io/)
[![rclone](https://img.shields.io/badge/rclone-0078D4?style=flat-square&logo=rclone&logoColor=white)](https://rclone.org/)

## 📑 Tabla de Contenidos
- [¿Por qué este proyecto?](#-por-qué-este-proyecto)
- [¿Qué resuelve este kit?](#-qué-resuelve-este-kit)
- [Guía rápida de instalación](#-guía-rápida-de-instalación)
- [La travesía: guía de recuperación](#-la-travesía-guía-de-recuperación-de-desastres)
- [El kit de automatización](#-el-kit-de-automatización-cómo-funciona)

## ❓ ¿Por qué este proyecto?

¿Has tenido que reiniciar tu servidor Proxmox o se quedó sin energía y, al volver, descubres que solo una parte arrancó? ¿O iniciaste una instalación limpia de Proxmox y quieres restaurar tus copias de seguridad de contenedores ya configurados —manteniéndolos al día y a salvo?

Si la respuesta es sí, este kit es para ti.

## 🚀 ¿Qué resuelve este kit?

Este repositorio reúne guías y scripts nacidos de una recuperación de desastres real. Su objetivo es volver tu Proxmox resiliente (capaz de recuperarse por sí mismo) automatizando tareas críticas que suelen fallar en microservidores:

- **Copias de seguridad automatizadas**
  - Backup del host (configuración de Proxmox en `/etc`)
  - Backup de LXC (datos) hacia la nube (p. ej., Google Drive)

- **Verificación de integridad**
  - Detección de archivos corruptos con `zstd -t`
  - Validación de logs de backup para detectar fallos de creación

- **Gestión segura de retención**
  - Sistema de carpeta staging (intermedia)
  - Preservación de última copia válida ante fallos

- **Gestión eficiente de almacenamiento**
  - Limpieza automática de papelera en Google Drive
  - Optimización para plan gratuito de 15 GB

- **Monitoreo y alertas**
  - Notificaciones en tiempo real vía Telegram/n8n
  - Alertas de éxitos, corrupciones y errores

- **Guías de recuperación**
  - Solución a errores comunes (`lxc.hook.pre-start`)
  - Resolución de problemas con permisos NTFS

## 🚀 Guía rápida de instalación

Esta sección es para quien quiera poner el kit en marcha sin leer todo el trasfondo. Asume que ya tienes un Proxmox VE funcionando.

### Requisitos previos

Asegúrate de contar con:

✅ Un servidor Proxmox VE en ejecución, con acceso root (o sudo)  
✅ Tu(s) disco(s) externo(s) de backup montado(s) (p. ej., en `/mnt/disco8tb`)  
✅ Una instancia de n8n (self-hosted o cloud)  
✅ Una cuenta de Google Drive  
✅ Un Bot Token de Telegram y tu Chat ID  

### Paso 1: Instalar dependencias

En el host Proxmox, ejecuta:

```bash
sudo apt update
sudo apt install rclone zstd -y

### Paso 2: Configurar rclone

Autoriza rclone para acceder a tu Google Drive:

```bash
rclone config
```

Sigue estos pasos interactivos:

1. `n` → New remote
2. `name` → Escribe `gdrive` (¡importante! los scripts usan este nombre)
3. `Storage` → Selecciona `drive` (Google Drive)
4. `client_id` → Dejar en blanco (Enter)
5. `client_secret` → Dejar en blanco (Enter)
6. `scope` → Selecciona `1` (Full access)
7. `root_folder_id` → Opcional (ID de tu carpeta de backups en Drive)
8. `service_account_file` → Dejar en blanco (Enter)
9. `Edit advanced config?` → `n`
10. `Use auto config?` → `n` (crucial en servidores sin monitor)
11. Cuando rclone muestre una URL (`https://accounts.google.com/...`):
    - Cópiala y ábrela en el navegador de tu PC
    - Autoriza con tu cuenta de Google (la de 15 GB si usas el plan gratuito)
    - Copia el código de verificación
    - Pégalo en la terminal de Proxmox
12. `Configure as team drive?` → `n`
13. `y` (Yes this is OK)
14. `q` (Quit)

### Paso 3: Preparar los flujos en n8n

1. En tu instancia de n8n, importa los tres workflows del directorio `/n8n_workflows`:
   - `lxc_backup_alerts.json`
   - `host_backup_alert.json`
   - `disk_alert.json`

2. Para cada workflow:
   - Actualiza el nodo de Telegram con tu Chat ID
   - Copia la Production URL del nodo Webhook
   - Activa el workflow (interruptor en verde)

> 💡 **Nota**: Usa la IP interna de tu n8n en la URL del webhook (p. ej., `http://10.0.0.62:5678/webhook/...`) y no un dominio externo. Así evitas errores de NAT loopback cuando Proxmox envíe alertas.

### Paso 4: Copiar y configurar los scripts

1. Clona este repositorio en el host Proxmox:
   ```bash
   git clone [URL_DE_TU_REPO_AQUI]
   cd [NOMBRE_DEL_REPO]
   ```

2. Copia los scripts a `/root/`:
   ```bash
   sudo cp ./scripts/*.sh /root/
   ```

3. Dales permisos de ejecución:
   ```bash
   sudo chmod +x /root/*.sh
   ```


4. Edita los scripts según tu entorno:

#### `sync_lxc_backups.sh`
```bash
sudo nano /root/sync_lxc_backups.sh
```
Variables a configurar:
- `LOCAL_DUMP_FOLDER`: ruta de dumps (p. ej., `/mnt/disco8tb/dump`)
- `LOCAL_STAGING_FOLDER`: carpeta staging (p. ej., `/mnt/disco8tb/cloud_staging`)
- `REMOTE_FOLDER`: remoto rclone (p. ej., `gdrive:LXC_Backups`)
- `N8N_WEBHOOK_URL`: URL del workflow `lxc_backup_alerts.json`

#### `backup_host.sh`
```bash
sudo nano /root/backup_host.sh
```
Variables a configurar:
- `DEST_DIR`: destino del backup del host (p. ej., `/mnt/disco8tb/host_backup`)
- `N8N_WEBHOOK_URL`: URL del workflow `host_backup_alert.json`

#### `check_disk.sh`
```bash
sudo nano /root/check_disk.sh
```
Variables a configurar:
- `N8N_WEBHOOK_URL`: URL del workflow `disk_alert.json`
- `DISK_PATH`: disco a monitorear (p. ej., `/mnt/disco8tb`)
- `THRESHOLD`: umbral de alerta en % (p. ej., `90`)

### Paso 5: Programar con crontab

1. Abre el crontab de root:
   ```bash
   sudo crontab -e
   ```

2. Pega este calendario seguro y escalonado (ejecución nocturna):
   ```bash
   # Se asume que tu tarea principal de backup LXC en Proxmox corre a las 3:00 AM

   # 4:00 AM: Backup de la configuración del host Proxmox
   0 4 * * * /root/backup_host.sh >/dev/null 2>&1

   # 4:30 AM: Verificar y sincronizar backups LXC a la nube
   30 4 * * * /root/sync_lxc_backups.sh >/dev/null 2>&1

   # 5:00 AM: Actualización automática del host Proxmox
   0 5 * * * apt update && apt dist-upgrade -y >/dev/null 2>&1

   # 6:00 AM: Comprobar espacio libre del disco principal
   0 6 * * * /root/check_disk.sh >/dev/null 2>&1
   ```

✨ **¡Listo!** Tu servidor queda automatizado y resiliente.

## 🔥 La travesía: guía de recuperación de desastres

> La Guía Rápida es para cuando todo funciona. Esta guía es para cuando todo se rompe.
> Es una bitácora real de lo que falló, lo que intentamos y lo que finalmente funcionó.

### Parte 1: El servidor murió (diagnóstico)

#### Síntoma
El servidor se congela en:
```
Loading initial ramdisk...
```
(justo después del menú de GRUB)

#### Lo que intentamos primero
- Arrancar en Recovery Mode de Proxmox (opciones avanzadas)
  - Resultado: También falló

#### Diagnóstico
Si tanto el kernel principal como el de recuperación fallan, el gestor de arranque o el initrd (initial ramdisk) están críticamente corruptos. Probamos a arrancar con un Live USB de Ubuntu y a usar chroot para reparar la instalación de Proxmox.

#### Intentos (que fallaron)
```bash
# Reconstruir todas las imágenes initramfs
update-initramfs -u -k all

# Regenerar la configuración de GRUB
update-grub

# Reinicializar la partición de arranque de Proxmox (ejemplo)
proxmox-boot-tool init /dev/nvme0n1p2
```

#### Decisión
Cuando las reparaciones con chroot también fallan, tardas más en resucitar un SO roto que en montar uno nuevo. Declaramos el SO del host como pérdida y procedimos con una reinstalación limpia de Proxmox.

### Parte 2: La reconstrucción (arreglos esenciales post-instalación)

Tras reinstalar Proxmox, los backups LXC restauran bien, pero el host aún no es estable. Aplica estos fixes primero.

#### 1️⃣ Red — IP estática

1. Edita la configuración de red:
   ```bash
   sudo nano /etc/network/interfaces


2. Cambia `vmbr0` de dhcp a static (usa tus direcciones):
   ```bash
   auto vmbr0
   iface vmbr0 inet static
       address 10.0.0.100/24
       gateway 10.0.0.1
       bridge-ports enp1s0f0
       bridge-stp off
       bridge-fd 0
   ```

3. Configura DNS para salida a internet:
   ```bash
   sudo nano /etc/resolv.conf
   ```
   ```bash
   nameserver 8.8.8.8
   nameserver 1.1.1.1
   ```

#### 2️⃣ SSH — "Host Identification Has Changed"

1. Error típico al primer SSH tras reinstalar:
   ```
   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
   ...
   Host key verification failed.
   ```

2. Solución (en tu PC local):
   ```bash
   ssh-keygen -R 10.0.0.100
   ssh root@10.0.0.100
   ```
   > 💡 Acepta la nueva clave cuando te pregunte (yes)

#### 3️⃣ Seguridad — hardening de SSH

1. Crea un usuario admin y dale sudo:
   ```bash
   adduser <tu_usuario_admin>
   usermod -aG sudo <tu_usuario_admin>
   ```

2. Prueba en otra terminal:
   ```bash
   ssh <tu_usuario_admin>@<tu_ip_proxmox>
   sudo whoami   # debería imprimir "root"
   ```

3. Desactiva el login de root:
   ```bash
   sudo nano /etc/ssh/sshd_config
   ```
   ```bash
   PermitRootLogin no
   ```
   ```bash
   sudo systemctl restart sshd
   ```

### Parte 3: El dolor de cabeza de LXC (arreglando mount points)

#### El problema típico
Log de inicio con error:
```bash
lxc.hook.pre-start: ... failed to run
__lxc_start: ... failed to initialize
startup for container '10X' failed
```


En casi todos los casos apunta a un punto de montaje fallido. Hay dos causas principales:

#### 1️⃣ "Mount points fantasma"

1. Inspecciona el config (reemplaza 101 con tu CT ID):
   ```bash
   cat /etc/pve/lxc/101.conf
   ```

2. Ejemplo de configuración problemática:
   ```bash
   # ✅ OK: disco raíz en el storage
   rootfs: DataStore01:101/vm-101-disk-1.raw,size=8G

   # ❌ MAL: montajes obsoletos del host antiguo
   mp0: /mnt/backup8tb/media,mp=/media
   mp1: /mnt/disco8tb,mp=/media/storage


3. Fix (borrar montajes fantasma):
   ```bash
   pct set 101 --delete mp0
   pct set 101 --delete mp1
   ```

> 💡 Arráncalo de nuevo; si inicia, re-agrega los montajes correctos desde la GUI (Hardware → Add → Mount Point)

#### 2️⃣ La trampa NTFS

1. Instala el driver y prepara el montaje:
   ```bash
   sudo apt install ntfs-3g -y
   sudo blkid
   # Ejemplo: /dev/sdb2: UUID="1A04B4DE04B4BE57" TYPE="ntfs" ...
   sudo mkdir -p /mnt/disco8tb
   ```

2. Configura el montaje en fstab:
   ```bash
   sudo nano /etc/fstab
   ```
   ```bash
   # Formato: UUID=[tu_uuid]  [ruta_montaje]   [filesystem]  [opciones]  0 0
   UUID=1A04B4DE04B4BE57  /mnt/disco8tb  ntfs-3g  rw,allow_other  0  0
   ```

3. Aplica y verifica:
   ```bash
   sudo mount -a
   mount | grep /mnt/disco8tb
   ```

## 🤖 El kit de automatización (cómo funciona)

Esto no son "solo scripts": es una tubería resiliente que valida backups, guarda copias fiables, sincroniza, limpia y alerta.

### 1️⃣ sync_lxc_backups.sh — lógica central

#### 🛡️ Seguridad y validación
- **Staging (red de seguridad)**
  - `cloud_staging/` conserva siempre el último backup válido por LXC
- **Verificación (doble check)**
  - Busca `ERROR:` en archivos `.log`
  - Ejecuta `zstd -t` en `.tar.zst` más reciente

#### 🔄 Sincronización y limpieza
- **Gestión de backups**
  - `rclone sync` replica staging → Google Drive (incremental)
  - Si falla un backup, se omite ese contenedor
  - Staging mantiene la copia buena previa
- **Optimización de espacio**
  - `rclone cleanup` vacía la papelera
  - Protección de cuota de 15 GB

#### ✅ Garantías
- No se sobreescribe la última copia válida con una mala
- Operaciones idempotentes
- Señales claras de fallo

### 2️⃣ Scripts auxiliares

#### backup_host.sh
- Crea `.tar.gz` de directorios críticos:
  - `/etc`: configuración del sistema
  - `/root`: scripts y configuraciones personalizadas
- Guarda archivos esenciales:
  - Configuración de red
  - `fstab`
  - `sshd_config`
  - Scripts de automatización

#### check_disk.sh
- Monitoreo proactivo del espacio
- Usa `df` para verificar uso de disco
- Alerta vía n8n si supera THRESHOLD (p. ej., 90%)

### 3️⃣ Workflows de alertas en n8n

#### Estructura del payload
```json
{
  "status": "exito",
  "success_count": 12,
  "fail_count": 1,
  "fail_reasons": "LXC-107: zstd integrity check failed"
}
```


#### Lógica de notificaciones
- Evaluación: `fail_count > 0`
  - ✅ False: "Éxito total"
  - ⚠️ True: "Éxito con fallos"

#### Formateo en Telegram
Para evitar errores de Markdown, usar HTML:

1. **Configuración básica**
   - Parse Mode: `HTML`
   - Formato negrita: `<b>texto</b>`
   - Bloques de código: `<pre>código</pre>`

2. **Ejemplo de plantilla**:
   ```html
   <b>Estado:</b> {{ $json.body.status }}<br/>
   <b>Exitosos:</b> {{ $json.body.success_count }}<br/>
   <b>Fallidos:</b> {{ $json.body.fail_count }}<br/>
   <b>Razones:</b>
   <pre>{{ $json.body.fail_reasons }}</pre>
   ```

> 💡 **Tip**: El formato HTML asegura que los mensajes se muestren correctamente en Telegram, independientemente de caracteres especiales o formato.