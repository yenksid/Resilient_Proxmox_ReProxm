# Resilient Proxmox: For Unstable Micro-Servers

> Automated disaster recovery for microservers that need to recover themselves

[![Proxmox](https://img.shields.io/badge/Proxmox-E97B00?style=flat-square&logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Bash](https://img.shields.io/badge/GNU%20Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![n8n](https://img.shields.io/badge/n8n-1A1A1A?style=flat-square&logo=n8n&logoColor=white)](https://n8n.io/)
[![rclone](https://img.shields.io/badge/rclone-0078D4?style=flat-square&logo=rclone&logoColor=white)](https://rclone.org/)

**English** | [**Español**](README-es.md)

## 📑 Table of Contents

- [Why This Project?](#-why-this-project)
- [What Does This Kit Solve?](#-what-does-this-kit-solve)
- [Quick Install Guide](#-quick-install-guide)
- [The Journey: Disaster Recovery Guide](#-the-journey-a-disaster-recovery-guide)
- [The Automation Kit](#-the-automation-kit--how-it-works)

## ❓ Why This Project?

Ever rebooted your Proxmox server or had it lose power, only to find just half of your services came back online? Or maybe you're starting a fresh Proxmox install and want to restore your container backups, keeping them configured, up-to-date, and safe?

If so, this kit is for you.

## 🚀 What Does This Kit Solve?

This repository is a collection of guides and scripts born from a real-world disaster recovery. Its goal is to make your Proxmox server resilient (capable of self-recovery) by automating the critical tasks that often fail on micro-servers:

- **Automated backups**
  - Backs up the **Host** (Proxmox config in `/etc`) and your **LXCs** (data) to the cloud (e.g., Google Drive)

- **Integrity verification**
  - Detects corrupt files with `zstd -t` before uploading
  - Reads `.log` files to identify creation failures

- **Safe retention management**
  - Uses an intermediate "staging" folder
  - Ensures your last valid cloud backup is **never deleted**, even if the daily backup fails

- **Google Drive quota management**
  - Automatically empties the trash with `rclone cleanup`
  - Protects your free 15GB limit

- **Real-time alerting**
  - Sends notifications to Telegram via n8n
  - Reports successes, corruptions, and upload errors

- **Post-rebuild guidance**
  - Solutions for `lxc.hook.pre-start` errors
  - NTFS disk permission troubleshooting

## 🚀 Quick Install Guide

This section is for those who want to get the kit running without reading the full backstory. It assumes you already have a functional Proxmox VE server.

### Prerequisites

Ensure you have the following:

✅ A running Proxmox VE server with `root` (or `sudo`) access  
✅ Your external backup disk(s) mounted (e.g., at `/mnt/disco8tb`)  
✅ An [n8n](https://n8n.io/) instance (self-hosted or cloud)  
✅ A Google Drive account  
✅ A Telegram Bot `Token` and your `Chat ID`

### Step 1: Install Dependencies (on Proxmox Host)

Log in to your Proxmox shell via SSH and install `rclone` (for cloud sync) and `zstd` (for integrity checks):

```bash
sudo apt update
sudo apt install rclone zstd -y
```

### Step 2: Configure rclone

Authorize rclone to access your Google Drive.

Run the configuration wizard:

```bash
rclone config
```

Follow these interactive steps:

1. `n` → New remote
2. `name` → `gdrive` ← This exact name is required; the scripts use it
3. `Storage` → `drive` (Google Drive)
4. `client_id` & `client_secret` → Leave blank (Press Enter)
5. `scope` → `1` (Full access)
6. `root_folder_id` → Optional (Paste the ID of your backup folder in Drive)
7. `service_account_file` → Leave blank (Press Enter)
8. `Edit advanced config?` → `n`
9. `Use auto config?` → `n` (Crucial for headless servers)
10. rclone will display a `https://accounts.google.com/...` URL
    - Copy it and open it in your PC's browser
    - Authorize with the correct Google Account (the one with 15GB of free space)
    - Copy the verification code Google gives you and paste it back into the Proxmox terminal
11. `Configure as team drive?` → `n`
12. `y` (Yes, this is OK)
13. `q` (Quit)

### Step 3: Set Up n8n Workflows

In your n8n instance, import the three workflows from the `/n8n_workflows` directory:

- `lxc_backup_alerts.json`
- `host_backup_alert.json`
- `disk_alert.json`

For each workflow:

- Update the Telegram node with your Chat ID
- Copy the Production URL from the Webhook node
- Activate the workflow (toggle the switch to green)

> 💡 **Note**: Use your n8n's internal IP in the webhook URL (e.g., `http://10.0.0.62:5678/webhook/...`), not an external domain. This prevents NAT loopback errors when Proxmox sends alerts.

### Step 4: Copy & Configure Scripts

1. Clone this repository onto your Proxmox host:
   ```bash
   git clone [YOUR_REPO_URL_HERE]
   cd [YOUR_REPO_NAME]
   ```

2. Copy the scripts to `/root/`:
   ```bash
   sudo cp ./scripts/*.sh /root/
   ```

3. Make them executable:
   ```bash
   sudo chmod +x /root/*.sh
   ```

4. Edit the scripts to match your environment:

#### `sync_lxc_backups.sh`

```bash
sudo nano /root/sync_lxc_backups.sh
```

Variables to configure:
- `LOCAL_DUMP_FOLDER`: Path to your dumps (e.g., `/mnt/disco8tb/dump`)
- `LOCAL_STAGING_FOLDER`: Staging path (e.g., `/mnt/disco8tb/cloud_staging`)
- `REMOTE_FOLDER`: rclone remote (e.g., `gdrive:LXC_Backups`)
- `N8N_WEBHOOK_URL`: URL from `lxc_backup_alerts.json`

#### `backup_host.sh`

```bash
sudo nano /root/backup_host.sh
```

Variables to configure:
- `DEST_DIR`: Host backup destination (e.g., `/mnt/disco8tb/host_backup`)
- `N8N_WEBHOOK_URL`: URL from `host_backup_alert.json`

#### `check_disk.sh`

```bash
sudo nano /root/check_disk.sh
```

Variables to configure:
- `N8N_WEBHOOK_URL`: URL from `disk_alert.json`
- `DISK_PATH`: Disk to monitor (e.g., `/mnt/disco8tb`)
- `THRESHOLD`: Alert percentage (e.g., `90`)

### Step 5: Schedule with crontab

1. Open the root crontab:
   ```bash
   sudo crontab -e
   ```

2. Paste this safe, staggered schedule at the end (for nightly execution):
   ```bash
   # Assuming your main Proxmox LXC backup task runs at 3:00 AM
   
   # 4:00 AM: Back up the Proxmox host configuration
   0 4 * * * /root/backup_host.sh >/dev/null 2>&1
   
   # 4:30 AM: Sync LXC backups to the cloud
   30 4 * * * /root/sync_lxc_backups.sh >/dev/null 2>&1
   
   # 5:00 AM: Auto-update packages (optional but recommended)
   0 5 * * * apt-get update && apt-get upgrade -y >/dev/null 2>&1
   
   # 6:00 AM: Check disk usage
   0 6 * * * /root/check_disk.sh >/dev/null 2>&1
   ```

3. Save and exit the editor.

✨ **You're all set!** Your server is now automated and resilient.

---

## 🔥 The Journey: A Disaster Recovery Guide

> The Quick Install is for when everything works. This guide is for when everything breaks.  
> It's a real-world log of what failed, what we tried, and what finally worked.

### Part 1: The Server Died (Diagnosis)

This kit exists because the host failed to boot after a restart. If you're here, you might be in the same spot.

#### Symptom

The server hangs at:
```
Loading initial ramdisk...
```
(right after the GRUB menu)

#### What We Tried First

- Booting Proxmox "Recovery Mode" from "Advanced options"
  - Result: It also failed

#### Diagnosis

If both the main kernel and recovery kernel fail, the bootloader or the initrd (initial ramdisk) is critically corrupted. We attempted recovery by booting a Live Ubuntu USB, then using chroot into the Proxmox install to repair it.

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

When chroot-based repairs also fail, you'll spend more time reviving a broken OS than rebuilding one. We declared the host OS a loss and proceeded with a clean Proxmox reinstall.

### Part 2: The Rebuild (Essential Post-Install Fixes)

After reinstalling Proxmox, LXC backups restore fine—but the host isn't stable yet. Apply these manual fixes first.

#### 1️⃣ Network — Set a Static IP

Your host needs a reliable address. Don't rely solely on DHCP reservations—set it directly on the host.

1. Log in to the Proxmox shell (root@pmox) and edit:
   ```bash
   sudo nano /etc/network/interfaces
   ```

2. Find `vmbr0` and switch it from dhcp to static (use your own addresses):
   ```bash
   auto vmbr0
   iface vmbr0 inet static
       address <your_proxmox_ip>/24
       gateway <your_gateway_ip>
       bridge-ports <your_interface_name>
       bridge-stp off
       bridge-fd 0
   ```

3. Add DNS so the host can reach the internet for updates:
   ```bash
   sudo nano /etc/resolv.conf
   ```
   ```bash
   nameserver 8.8.8.8
   nameserver 1.1.1.1
   ```

#### 2️⃣ SSH — "Host Identification Has Changed"

After a clean rebuild, your first SSH will likely be blocked:

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
...
Host key verification failed.
```

This is normal: your PC cached the old host key. The rebuilt server has a new fingerprint.

1. Fix (on your local PC):
   ```bash
   ssh-keygen -R <your_proxmox_ip>
   ```

2. Then try again:
   ```bash
   ssh root@<your_proxmox_ip>
   ```

3. Accept the new key when prompted (`yes`)

#### 3️⃣ Security — Harden SSH (Disable root login)

This is the most important basic hardening step.

1. Create an admin user on the host:
   ```bash
   adduser <your_admin_user>
   ```

2. Grant sudo rights:
   ```bash
   usermod -aG sudo <your_admin_user>
   ```

3. Test in a second terminal:
   ```bash
   ssh <your_admin_user>@<your_proxmox_ip>
   sudo whoami   # should print "root"
   ```

4. Only if the test works, disable direct root login in your first terminal:
   ```bash
   sudo nano /etc/ssh/sshd_config
   ```

5. Find (or add) and set:
   ```bash
   PermitRootLogin no
   ```

6. Restart SSH:
   ```bash
   sudo systemctl restart sshd
   ```

7. From now on, log in as `<your_admin_user>` and use `sudo` for admin tasks

### Part 3: The LXC Headache (Fixing Mount-Point Errors)

After a clean reinstall, the most annoying issues are usually LXC startup failures. You restore from backup, click "Start," and it dies with a generic error.

#### Typical startup log:

```
lxc.hook.pre-start: ... failed to run
__lxc_start: ... failed to initialize
startup for container '10X' failed
```

In almost every case, this points to a failed storage mount point. We've seen two primary causes.

#### Cause 1️⃣ — "Ghost" Mount Points

Backups preserve not only data but also the container config (e.g., `101.conf`), which includes references to old disk mounts.

**Problem**

Your new host may use different paths (e.g., `/mnt/disco8tb`) or you may have stale `mpX` entries that no longer exist. LXC tries to mount those paths and fails.

1. Inspect the config (replace 101 with your CT ID):
   ```bash
   cat /etc/pve/lxc/101.conf
   ```

2. You'll see something like:
   ```bash
   # OK: root disk on storage
   rootfs: DataStore01:101/vm-101-disk-1.raw,size=8G

   # BAD: stale mounts from the old host
   mp0: /mnt/backup8tb/media,mp=/media
   mp1: /mnt/disco8tb,mp=/media/storage
   ```

3. Fix (delete ghost mounts):
   ```bash
   pct set 101 --delete mp0
   pct set 101 --delete mp1
   ```

4. Try starting the container again. If it boots, re-add the correct mount points via the Proxmox GUI (Hardware → Add → Mount Point)

#### Cause 2️⃣ — The NTFS Filesystem Trap

If your external disks (e.g., that 8 TB drive) are formatted as NTFS for Windows compatibility, you'll likely hit permission mapping issues.

**Problem**

Linux can read NTFS, but its permission model doesn't map cleanly to LXC. Even privileged containers can fail the pre-start hook when the host mount doesn't expose owners/permissions in a usable way.

**Fix — mount NTFS with permissive options on the host**

1. Install the proper driver:
   ```bash
   sudo apt install ntfs-3g -y
   ```

2. Find your disk's UUID:
   ```bash
   sudo blkid
   ```
   Example output snippet:
   ```
   # /dev/sdb2: UUID="1A04B4DE04B4BE57" TYPE="ntfs" ...
   ```

3. Create the mount point (if needed) and make it persistent in fstab:
   ```bash
   sudo mkdir -p /mnt/disco8tb
   sudo nano /etc/fstab
   ```

4. Add the line (replace with your UUID and mount path):
   ```bash
   # Format: UUID=[your_uuid]  [mount_path]   [filesystem]  [options]          0 0
   UUID=1A04B4DE04B4BE57  /mnt/disco8tb  ntfs-3g  rw,allow_other  0  0
   ```
   - `ntfs-3g`: reliable NTFS driver
   - `rw,allow_other`: exposes the mount broadly so LXC can access it

5. Apply and verify:
   ```bash
   sudo mount -a
   mount | grep /mnt/disco8tb
   ```

With the host NTFS mount set this way, your LXC containers should start cleanly.

---

## 🤖 The Automation Kit — How It Works

This isn't "just scripts." It's a resilient pipeline that validates backups, stages known-good copies, syncs to the cloud, cleans up, and alerts—so you can trust it and troubleshoot confidently.

### 1️⃣ sync_lxc_backups.sh — Core Logic

Designed to prevent bad uploads and accidental data loss. It does far more than copy files.

#### 🛡️ Staging (safety net)

Creates a `cloud_staging/` folder that must always hold the latest valid backup per LXC. If today's LXC-101 backup is corrupt, yesterday's known-good copy stays in staging.

**Result**: you never sync a bad backup or delete your last good one.

#### ✅ Verification (two checks before staging)

- **Log check**: scans the newest `.log` for `ERROR:` (case-insensitive) to detect creation failures
- **Success check**: Requires a success mark (e.g., `INFO: backup finished`) in the `.log`
- **Integrity check**: runs `zstd -t -T0` on the newest `.tar.zst` to ensure it's decompressible
- **Stability check**: `wait_stable_size` ensures the file isn't actively being written

#### 🔔 Alerting (fail fast, skip safely)

If any check fails, the script sends a detailed alert to n8n and skips that container. Staging retains the previous valid backup.

#### 🔄 Cloud sync (incremental & fast)

Uses `rclone sync` to mirror `cloud_staging/` to Google Drive—only new/changed files are transferred.

#### 🗑️ Trash cleanup (quota-friendly)

Runs `rclone sync ... --drive-use-trash=false` to permanently delete old files, protecting your 15 GB free quota (bypassing the trash).

#### ✅ Guarantees

- Never overwrites your last known-good backup with a bad one
- Idempotent daily runs (safe to re-run)
- Clear signals when something goes wrong

### 2️⃣ backup_host.sh & check_disk.sh — Essential Helpers

#### backup_host.sh

Creates a `.tar.gz` snapshot of `/etc` and `/root`—capturing network config, `fstab`, `sshd_config`, and these scripts. This is your host's "brain" in a single file.

#### check_disk.sh

Checks disk usage with `df`. If usage exceeds `THRESHOLD` (e.g., 90%), it sends a concise alert to n8n—so you fix storage pressure before backups start failing.

### 3️⃣ n8n Alerting Workflows — Smart, Readable Notifications

The scripts POST JSON to n8n webhooks; n8n transforms that into clear Telegram messages.

#### IF logic (in lxc_backup_alerts.json)

Example payload:

```json
{
  "status": "exito",
  "success_count": 12,
  "fail_count": 1,
  "fail_reasons": "LXC-107: zstd integrity check failed"
}
```

The IF node evaluates: is `fail_count` (as a Number) Larger than 0?

- **True**: send "Success with Failures" (includes the reasons)
- **False**: send "Total Success"

#### Fixing Telegram's Formatting Pitfalls

**Error you'll see without our templates:**

```
Bad Request: can't parse entities: Character '_' is reserved
```

**Why**: Telegram's Markdown parser treats `_` / `-` in filenames (e.g., `vzdump-lxc-107...`) as formatting.

**Fix (applied in all Telegram nodes):**

- Parse Mode: set to **HTML** (more predictable than Markdown)
- Use `<b>` for bold instead of `*text*`
- Wrap raw error lists / filenames in `<pre>...</pre>` so Telegram doesn't parse them:

```html
<b>Status:</b> {{ $json.body.status }}<br/>
<b>Succeeded:</b> {{ $json.body.success_count }}<br/>
<b>Failed:</b> {{ $json.body.fail_count }}<br/>
<b>Reasons:</b>
<pre>{{ $json.body.fail_reasons }}</pre>
```

---

## 📝 License

This project is released under the MIT License. See [LICENSE](LICENSE) for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## 📧 Support

For questions, issues, or feedback, please open an issue on this repository.
