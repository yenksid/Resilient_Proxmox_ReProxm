# Resilient Proxmox: For Unstable Micro-Servers
> Automated disaster recovery for microservers that need to recover themselves

[![Proxmox](https://img.shields.io/badge/Proxmox-E97B00?style=flat-square&logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Bash](https://img.shields.io/badge/GNU%20Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![n8n](https://img.shields.io/badge/n8n-1A1A1A?style=flat-square&logo=n8n&logoColor=white)](https://n8n.io/)
[![rclone](https://img.shields.io/badge/rclone-0078D4?style=flat-square&logo=rclone&logoColor=white)](https://rclone.org/)

**English** | [**Español**](README-es.md)

## 📑 Table of Contents
- [Why This Project?](#why-this-project)
- [What Does This Kit Solve?](#what-does-this-kit-solve)
- [Quick Install Guide](#quick-install-guide)
- [The Journey: A Disaster Recovery Guide](#the-journey-a-disaster-recovery-guide)
- [The Automation Kit — How It Works](#the-automation-kit--how-it-works)
- [License](#license)
- [Contributing](#contributing)
- [Support](#support)

---

## ❓ Why This Project?
Ever rebooted your Proxmox server or had it lose power, only to find just half of your services came back online? Or maybe you're starting a fresh Proxmox install and want to restore your container backups, keeping them configured, up-to-date, and safe?

If so, this kit is for you.

## 🚀 What Does This Kit Solve?
This repository is a collection of guides and scripts born from a real-world disaster recovery. Its goal is to make your Proxmox server resilient (capable of self-recovery) by automating the critical tasks that often fail on micro-servers:

- **Automated backups**
  - Backs up the **Host** (Proxmox config in `/etc` **and** `/root`) and your **LXCs** (data) to the cloud (e.g., Google Drive).

- **Integrity verification**
  - Detects corrupt files with `zstd -t` before uploading.
  - Reads `.log` files to identify creation failures and **requires a clear success mark** (e.g., `INFO: backup finished`) before staging/syncing.
  - Uses a stability guard (e.g., `wait_stable_size`) to ensure files aren’t still being written.

- **Safe retention management**
  - Uses an intermediate “staging” folder.
  - Ensures your last valid cloud backup is **never deleted**, even if the daily backup fails.

- **Google Drive quota management**
  - **Bypasses the trash** using `rclone sync ... --drive-use-trash=false` so old files are deleted **permanently**.
  - Protects your free 15 GB limit by preventing the trash from filling up.

- **Real-time alerting**
  - Sends notifications to Telegram via n8n.
  - Reports successes, corruptions, and **critical script failures**.

- **Post-rebuild guidance**
  - Solutions for `lxc.hook.pre-start` errors.
  - NTFS disk permission troubleshooting.

---

## 🚀 Quick Install Guide
This section is for those who want to get the kit running without reading the full backstory. It assumes you already have a functional Proxmox VE server.

### Prerequisites
Ensure you have the following:

- ✅ A running Proxmox VE server with `root` (or `sudo`) access  
- ✅ Your external backup disk(s) mounted (e.g., at `/mnt/disco8tb`)  
- ✅ An [n8n](https://n8n.io/) instance (self-hosted or cloud)  
- ✅ A Google Drive account  
- ✅ A Telegram Bot **Token** and your **Chat ID**

### Step 1: Install Dependencies (on Proxmox Host)
Log in to your Proxmox shell via SSH and install `rclone` (for cloud sync) and `zstd` (for integrity checks):

```bash
sudo apt update
sudo apt install rclone zstd -y
Step 2: Configure rclone
Authorize rclone to access your Google Drive.

Run the configuration wizard:

bash
Copiar código
rclone config
Follow these interactive steps:

n → New remote

name → gdrive ← This exact name is required; the installer and scripts use it

Storage → drive (Google Drive)

client_id & client_secret → Leave blank (Press Enter)

scope → 1 (Full access)

root_folder_id → Optional (Paste the ID of your backup folder in Drive)

service_account_file → Leave blank (Press Enter)

Edit advanced config? → n

Use auto config? → n (Crucial for headless servers)

rclone will display a https://accounts.google.com/... URL.

Open it in your PC’s browser

Authorize with the correct Google Account

Paste the verification code back into the Proxmox terminal

Configure as team drive? → n

y (Yes, this is OK)

q (Quit)

Step 3: Set Up n8n Workflows
In your n8n instance, import the three workflows from the /n8n_workflows directory:

lxc_backup_alerts.json

host_backup_alert.json

disk_alert.json

For each workflow:

Update the Telegram node with your Chat ID and Bot credentials (Token)

Copy the Production URL from the Webhook node

Activate the workflow (toggle the switch to green)

💡 Note: Use your n8n’s internal IP in the webhook URL (e.g., http://10.0.0.62:5678/webhook/...), not an external domain. This prevents NAT loopback errors when Proxmox sends alerts.

Step 4: Run the Installer
Use the automated installer to configure paths, webhooks, and cron safely:

bash
Copiar código
git clone https://github.com/yenksid/Resilient_Proxmox_ReProxm.git
cd Resilient_Proxmox_ReProxm
chmod +x install.sh
sudo ./install.sh
The script will prompt you for:

Backup disk path (e.g., /mnt/disco8tb)

rclone remote name (e.g., gdrive) and remote folder (e.g., LXC_Backups)

The three n8n webhook URLs you copied in Step 3

Disk usage threshold (e.g., 90)

It will copy scripts into /root/, inject your configuration, and set up the crontab.

Step 5: Verify crontab
The installer configures the crontab automatically. Verify it:

bash
Copiar código
sudo crontab -l
It should contain a block like this. The PATH= line is critical so cron can find pct, rclone, ionice, etc.:

bash
Copiar código
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# >>> PROXMOX_RESILIENT_KIT ---
# 4:00 AM: Back up the Proxmox host configuration (/etc and /root)
0 4 * * * /root/backup_host.sh >/dev/null 2>&1
# 4:30 AM: Verify and sync LXC backups to the cloud (with low I/O/CPU priority)
30 4 * * * ionice -c 3 nice -n 19 /root/sync_lxc_backups.sh >/dev/null 2>&1
# 5:00 AM: Auto-update the Proxmox host
0 5 * * * apt update && apt dist-upgrade -y >/dev/null 2>&1
# 6:00 AM: Check free space on the main backup disk
0 6 * * * /root/check_disk.sh >/dev/null 2>&1
# <<< PROXMOX_RESILIENT_KIT ---
🔥 The Journey: A Disaster Recovery Guide
Part 1: The Server Died (Diagnosis)
This kit exists because the host failed to boot after a restart. If you're here, you might be in the same spot.

Symptom

The server hangs at:

sql
Copiar código
Loading initial ramdisk...
(right after the GRUB menu)

What We Tried First

Booting Proxmox “Recovery Mode” from “Advanced options”

Result: It also failed

Diagnosis
If both the main kernel and recovery kernel fail, the bootloader or the initrd (initial ramdisk) is critically corrupted. We attempted recovery by booting a Live Ubuntu USB, then using chroot into the Proxmox install to repair it.

Attempts (That Failed)

bash
Copiar código
# Rebuild all initramfs images
update-initramfs -u -k all

# Regenerate GRUB config
update-grub

# Re-initialize Proxmox boot partition (example device)
proxmox-boot-tool init /dev/sdX#
Decision
When chroot-based repairs also fail, you'll spend more time reviving a broken OS than rebuilding one. We declared the host OS a loss and proceeded with a clean Proxmox reinstall.

Part 2: The Rebuild (Essential Post-Install Fixes)
After reinstalling Proxmox, LXC backups restore fine—but the host isn't stable yet. Apply these manual fixes first.

1️⃣ Network — Set a Static IP
Your host needs a reliable address. Don’t rely solely on DHCP reservations—set it directly on the host.

Edit interfaces:

bash
Copiar código
sudo nano /etc/network/interfaces
Switch vmbr0 from DHCP to static (use your own addresses):

ini
Copiar código
auto vmbr0
iface vmbr0 inet static
    address <your_proxmox_ip>/24
    gateway <your_gateway_ip>
    bridge-ports <your_interface_name>
    bridge-stp off
    bridge-fd 0
Add DNS for updates:

bash
Copiar código
sudo nano /etc/resolv.conf
ini
Copiar código
nameserver 8.8.8.8
nameserver 1.1.1.1
2️⃣ SSH — “Host Identification Has Changed”
After a clean rebuild, your first SSH will likely be blocked:

python
Copiar código
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
...
Host key verification failed.
This is normal: your PC cached the old host key. The rebuilt server has a new fingerprint.

Fix (on your local PC):

bash
Copiar código
ssh-keygen -R <your_proxmox_ip>
Then try again:

bash
Copiar código
ssh root@<your_proxmox_ip>
Accept the new key when prompted (yes).

3️⃣ Security — Harden SSH (Disable root login)
This is the most important basic hardening step.

Create an admin user on the host:

bash
Copiar código
adduser <your_admin_user>
Grant sudo rights:

bash
Copiar código
usermod -aG sudo <your_admin_user>
Test in a second terminal:

bash
Copiar código
ssh <your_admin_user>@<your_proxmox_ip>
sudo whoami   # should print "root"
Only if the test works, disable direct root login:

bash
Copiar código
sudo nano /etc/ssh/sshd_config
ini
Copiar código
PermitRootLogin no
Restart SSH:

bash
Copiar código
sudo systemctl restart sshd
From now on, log in as <your_admin_user> and use sudo for admin tasks.

Part 3: The LXC Headache (Fixing Mount-Point Errors)
After a clean reinstall, the most annoying issues are usually LXC startup failures. You restore from backup, click “Start,” and it dies with a generic error.

Typical startup log:

vbnet
Copiar código
lxc.hook.pre-start: ... failed to run
__lxc_start: ... failed to initialize
startup for container '10X' failed
In almost every case, this points to a failed storage mount point. We’ve seen two primary causes.

Cause 1️⃣ — “Ghost” Mount Points
Backups preserve not only data but also the container config (e.g., 101.conf), which includes references to old disk mounts.

Problem
Your new host may use different paths (e.g., /mnt/disco8tb) or you may have stale mpX entries that no longer exist. LXC tries to mount those paths and fails.

Inspect the config (replace 101 with your CT ID):

bash
Copiar código
cat /etc/pve/lxc/101.conf
You’ll see something like:

ini
Copiar código
# OK: root disk on storage
rootfs: DataStore01:101/vm-101-disk-1.raw,size=8G

# BAD: stale mounts from the old host
mp0: /mnt/backup8tb/media,mp=/media
mp1: /mnt/disco8tb,mp=/media/storage
Fix (delete ghost mounts):

bash
Copiar código
pct set 101 --delete mp0
pct set 101 --delete mp1
Try starting the container again. If it boots, re-add the correct mount points via the Proxmox GUI (Hardware → Add → Mount Point).

Cause 2️⃣ — The NTFS Filesystem Trap
If your external disks (e.g., that 8 TB drive) are formatted as NTFS for Windows compatibility, you’ll likely hit permission mapping issues.

Problem
Linux can read NTFS, but its permission model doesn’t map cleanly to LXC. Even privileged containers can fail the pre-start hook when the host mount doesn’t expose owners/permissions in a usable way.

Fix — mount NTFS with permissive options on the host

Install the driver:

bash
Copiar código
sudo apt install ntfs-3g -y
Find your disk’s UUID:

bash
Copiar código
sudo blkid
Example:

bash
Copiar código
/dev/sdb2: UUID="1A04B4DE04B4BE57" TYPE="ntfs" ...
Create the mount point (if needed) and make it persistent in fstab:

bash
Copiar código
sudo mkdir -p /mnt/disco8tb
sudo nano /etc/fstab
Add the line (replace with your UUID and mount path):

ini
Copiar código
# Format: UUID=[your_uuid]  [mount_path]   [filesystem]  [options]          0 0
UUID=1A04B4DE04B4BE57  /mnt/disco8tb  ntfs-3g  rw,allow_other  0  0
ntfs-3g: reliable NTFS driver

rw,allow_other: exposes the mount broadly so LXC can access it

Apply and verify:

bash
Copiar código
sudo mount -a
mount | grep /mnt/disco8tb
With the host NTFS mount set this way, your LXC containers should start cleanly.

🤖 The Automation Kit — How It Works
This isn’t “just scripts.” It’s a resilient pipeline that validates backups, stages known-good copies, syncs to the cloud, cleans up, and alerts—so you can trust it and troubleshoot confidently.

1️⃣ sync_lxc_backups.sh — Core Logic
Designed to prevent bad uploads and accidental data loss. It does far more than copy files.

🛡️ Staging (safety net)
Creates a cloud_staging/ folder that must always hold the latest valid backup per LXC. If today’s LXC-101 backup is corrupt, yesterday’s known-good copy stays in staging.
Result: you never sync a bad backup or delete your last good one.

✅ Verification (strict, multi-step)

Log check: scans the newest .log for ERROR: (case-insensitive) to detect creation failures

Success check: requires a success mark (e.g., INFO: backup finished) in the .log

Integrity check: runs zstd -t -T0 on the newest .tar.zst to ensure it’s decompressible

Stability check: wait_stable_size ensures the file isn’t actively being written

🔔 Alerting (fail fast, skip safely)
If any check fails, the script sends a detailed alert to n8n and skips that container. Staging retains the previous valid backup.

🔄 Cloud sync (incremental & quota-friendly)

Uses rclone sync to mirror cloud_staging/ to Google Drive.

Runs with --drive-use-trash=false so deletions are permanent (prevents the 15 GB trash from filling up).

✅ Guarantees

Never overwrites your last known-good backup with a bad one

Idempotent daily runs (safe to re-run)

Clear signals when something goes wrong

2️⃣ backup_host.sh & check_disk.sh — Essential Helpers
backup_host.sh
Creates a .tar.gz snapshot of /etc and /root—capturing network config, fstab, sshd_config, and these scripts. This is your host’s “brain” in a single file.

check_disk.sh
Checks disk usage with df. If usage exceeds THRESHOLD (e.g., 90%), it sends a concise alert to n8n—so you fix storage pressure before backups start failing.

3️⃣ n8n Alerting Workflows — Smart, Readable Notifications
The scripts POST JSON to n8n webhooks; n8n transforms that into clear Telegram messages.

IF logic (in lxc_backup_alerts.json)

Example payload:

json
Copiar código
{
  "status": "success",
  "success_count": 12,
  "fail_count": 1,
  "fail_reasons": "LXC-107: zstd integrity check failed"
}
The IF node evaluates: is fail_count (as a Number) greater than 0?

True: send “Success with Failures” (includes the reasons)

False: send “Total Success”

Fixing Telegram’s Formatting Pitfalls

Error you’ll see without our templates:

rust
Copiar código
Bad Request: can't parse entities: Character '_' is reserved
Why: Telegram’s Markdown parser treats _ / - in filenames (e.g., vzdump-lxc-107...) as formatting.

Fix (applied in all Telegram nodes):

Parse Mode: set to HTML (more predictable than Markdown)

Use <b> for bold instead of *text*

Wrap raw error lists / filenames in <pre>...</pre> so Telegram doesn’t parse them:

html
Copiar código
<b>Status:</b> {{ $json.body.status }}<br/>
<b>Succeeded:</b> {{ $json.body.success_count }}<br/>
<b>Failed:</b> {{ $json.body.fail_count }}<br/>
<b>Reasons:</b>
<pre>{{ $json.body.fail_reasons }}</pre>
📝 License
This project is released under the MIT License. See LICENSE for details.

🤝 Contributing
Contributions are welcome! Please feel free to submit issues or pull requests.

📧 Support
For questions, issues, or feedback, please open an issue on this repository.