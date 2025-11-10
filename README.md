English | [Español](README-es.md)
# Resilient Proxmox (ReProxm)
![Proxmox](https://img.shields.io/badge/Proxmox-E97B00?style=flat-square&logo=proxmox&logoColor=white)
![Bash](https://img.shields.io/badge/GNU%20Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![n8n](https://img.shields.io/badge/n8n-1A1A1A?style=flat-square&logo=n8n&logoColor=white)
![rclone](https://img.shields.io/badge/rclone-0078D4?style=flat-square&logo=rclone&logoColor=white)
> A comprehensive toolkit for unstable micro-servers

## 🤔 The Problem

Ever rebooted your Proxmox server or had it lose power, only to find just half of your services came back online? Or maybe you're starting a fresh Proxmox install and want to restore your container backups, keeping them configured, up-to-date, and safe?

If so, this kit is for you.

## 🚀 Features

This repository is a collection of guides and scripts born from a real-world disaster recovery. Its goal is to make your Proxmox server resilient (capable of self-recovery) by automating the critical tasks that often fail on micro-servers:

### Automated Backup System
- ✨ Complete backup of both Host (Proxmox config in `/etc`) and LXCs to the cloud
- 🔍 Built-in integrity verification using `zstd -t` and log file analysis
- 🗄️ Safe retention management with staging folders
- ♻️ Smart Google Drive quota management

### Monitoring & Alerts
- 📱 Real-time Telegram notifications via n8n
- 🚨 Instant alerts for:
  - Backup successes
  - File corruptions
  - Upload errors

### Recovery Tools
- 🛠️ Comprehensive post-rebuild guide
- 🔧 Solutions for common issues:
  - `lxc.hook.pre-start` errors
  - NTFS disk permission problems

 # Resilient Proxmox (ReProxm) — Quick Install Guide

> A compact, GitHub-ready guide to set up automated Proxmox backups with rclone, n8n alerts and Telegram notifications.

This guide assumes you already have a working Proxmox VE installation and root (or sudo) access.

## Prerequisites

- A running Proxmox VE server with root (or sudo) access
- External backup disk(s) mounted (example: `/mnt/disco8tb`)
- An n8n instance (self-hosted or cloud)
- A Google Drive account
- A Telegram Bot token and your Chat ID

## Overview

High level steps:

1. Install required packages (`rclone`, `zstd`)
2. Configure `rclone` to access Google Drive (remote name: `gdrive`)
3. Import and configure n8n workflows for alerts
4. Copy and configure backup/sync scripts to `/root/`
5. Schedule the scripts in root's crontab

---

## 1 — Install dependencies (on Proxmox host)

SSH into your Proxmox host and run:

```bash
sudo apt update
sudo apt install rclone zstd -y
```

## 2 — Configure rclone

Run the interactive setup:

```bash
rclone config
```

Follow the prompts (summary):

- Choose `n` to create a new remote
- Name the remote: `gdrive` (this exact name is required by the scripts)
- Storage: `drive` (Google Drive)
- `client_id` / `client_secret`: leave blank (press Enter)
- Scope: choose full access (usually `1`)
- `root_folder_id`: optional (paste a Drive folder ID if you want)
- `service_account_file`: leave blank
- Advanced config? `n`
- Auto config? `n` (important for headless servers)

rclone will print a URL starting with `https://accounts.google.com/...`. Open that URL in a browser on your PC, authorize the account, copy the verification code and paste it back into the Proxmox terminal. When asked about team drives choose `n` unless you use one.

When finished, confirm (`y`) and quit (`q`).

## 3 — Set up n8n workflows

In your n8n instance import the JSON workflow files located in the repository's `n8n_workflows` directory:

- `lxc_backup_alerts.json`
- `host_backup_alert.json`
- `disk_alert.json`

For each workflow:

- Update the Telegram node with your Chat ID
- Copy the Webhook node's production URL (use the webhook URL in the scripts)
- Activate the workflow (toggle on)

Important: Use your n8n internal IP in webhook URLs (for example `http://10.0.0.62:5678/webhook/...`) rather than an external domain to avoid NAT loopback problems when Proxmox posts to the webhook.

## 4 — Copy & configure scripts

Clone the repository to the Proxmox host:

```bash
git clone [YOUR_REPO_URL_HERE]
cd [YOUR_REPO_NAME]
```

Copy the scripts to `/root/` and make them executable:

```bash
sudo cp ./scripts/*.sh /root/
sudo chmod +x /root/*.sh
```

Edit the following scripts and set the variables to match your environment:

- `sync_lxc_backups.sh`
	- `LOCAL_DUMP_FOLDER`: e.g. `/mnt/disco8tb/dump`
	- `LOCAL_STAGING_FOLDER`: e.g. `/mnt/disco8tb/cloud_staging`
	- `REMOTE_FOLDER`: rclone remote, e.g. `gdrive:LXC_Backups`
	- `N8N_WEBHOOK_URL`: webhook URL from `lxc_backup_alerts.json`

- `backup_host.sh`
	- `DEST_DIR`: e.g. `/mnt/disco8tb/host_backup`
	- `N8N_WEBHOOK_URL`: webhook URL from `host_backup_alert.json`

- `check_disk.sh`
	- `N8N_WEBHOOK_URL`: webhook URL from `disk_alert.json`
	- `DISK_PATH`: path to monitor, e.g. `/mnt/disco8tb`
	- `THRESHOLD`: percent to alert at, e.g. `90`

Edit with your favorite editor, for example:

```bash
sudo nano /root/sync_lxc_backups.sh
```

## 5 — Schedule with crontab

Edit root's crontab:

```bash
sudo crontab -e
```

Add this suggested nightly schedule (adjust times as needed):

```cron
# 4:00 AM: Back up the Proxmox host configuration
0 4 * * * /root/backup_host.sh >/dev/null 2>&1

# 4:30 AM: Verify and sync LXC backups to the cloud
30 4 * * * /root/sync_lxc_backups.sh >/dev/null 2>&1

# 5:00 AM: Auto-update the Proxmox host
0 5 * * * apt update && apt dist-upgrade -y >/dev/null 2>&1

# 6:00 AM: Check free space on the main backup disk
0 6 * * * /root/check_disk.sh >/dev/null 2>&1
```

Save and exit the editor.

---

## Notes & tips

- Keep an eye on your Google Drive usage (Drive free tier is 15GB unless you have more storage available).
- Test the n8n webhooks manually after importing to ensure the webhook URLs and Telegram nodes work.
- Consider rotating logs and monitoring disk usage so backups don't fill the drive.

## You're all set

After configuration the server should automatically back up the host, verify LXC backups, sync to Google Drive and send Telegram alerts via n8n.

If you want, I can also:

- Add a short Table of Contents
- Create a sample `.env.example` or `config` template for the scripts
- Add `README` badges or a small troubleshooting section

---

# 🔥 The Journey: A Disaster Recovery Guide

The Quick Install is for when everything works. This guide is for when everything breaks.

It’s a real-world log of what failed, what we tried, and what finally worked.

## Part 1: The Server Died (Diagnosis)

This kit exists because the host failed to boot after a restart. If you’re here, you might be in the same spot.

### Symptom

The server hangs at:

```
Loading initial ramdisk... (right after the GRUB menu).
```

### What We Tried First

Booting Proxmox "Recovery Mode" from “Advanced options.” It also failed.

### Diagnosis

If both the main kernel and recovery kernel fail, the bootloader or the initrd (initial ramdisk) is critically corrupted. We attempted recovery by booting a Live Ubuntu USB, then using chroot into the Proxmox install to repair it.

### Attempts (That Failed)

```bash
# Rebuild all initramfs images
update-initramfs -u -k all

# Regenerate GRUB config
update-grub

# Re-initialize Proxmox boot partition (example device)
proxmox-boot-tool init /dev/sdX#
```

### Decision

When chroot-based repairs also fail, you’ll spend more time reviving a broken OS than rebuilding one. We declared the host OS a loss and proceeded with a clean Proxmox reinstall.

## Part 2: The Rebuild (Essential Post-Install Fixes)

After reinstalling Proxmox, LXC backups restore fine—but the host isn’t stable yet. Apply these manual fixes first.

### 1. Network — Set a Static IP

Your host needs a reliable address. Don’t rely solely on DHCP reservations—set it directly on the host.

Log in to the Proxmox shell (root@pmox) and edit:

```bash
sudo nano /etc/network/interfaces
```

Find `vmbr0` and switch it from `dhcp` to `static` (use your own addresses):

```
auto vmbr0
iface vmbr0 inet static
    address <your_proxmox_ip>/24
    gateway <your_gateway_ip>
    bridge-ports <your_interface_name>
    bridge-stp off
    bridge-fd 0
```

Add DNS so the host can reach the internet for updates:

```bash
sudo nano /etc/resolv.conf
```

Add (or adjust) a resolver, for example:

```
nameserver 8.8.8.8
nameserver 1.1.1.1
```

### 2. SSH — "Host Identification Has Changed"

After a clean rebuild, your first ssh will likely be blocked:

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY! ... Host key verification failed.
```

This is normal: your PC cached the old host key. The rebuilt server has a new fingerprint.

Fix (on your local PC):

```bash
ssh-keygen -R <your_proxmox_ip>
```

Then try again:

```bash
ssh root@<your_proxmox_ip>
```

Accept the new key when prompted (yes).

### 3. Security — Harden SSH (Disable root login)

This is the most important basic hardening step.

Create an admin user on the host:

```bash
adduser <your_admin_user>
```

Grant sudo rights:

```bash
usermod -aG sudo <your_admin_user>
```

Test in a second terminal:

```bash
ssh <your_admin_user>@<your_proxmox_ip>
sudo whoami   # should print "root"
```

Only if the test works, disable direct root login in your first terminal:

```bash
sudo nano /etc/ssh/sshd_config
```

Find (or add) and set:

```
PermitRootLogin no
```

Restart SSH:

```bash
sudo systemctl restart sshd
```

From now on, log in as `<your_admin_user>` and use `sudo` for admin tasks.

## Helpful Tips

- Always keep a backup of your data and configuration before attempting any recovery or rebuild process.
- Document each step you take during recovery for future reference and to help others who might face similar issues.
- Consider using a dedicated management network for Proxmox to avoid potential network-related issues during recovery.
- Regularly update your Proxmox installation and keep the system packages up to date to minimize the risk of encountering known issues.

# Task 4 — The LXC Headache (Fixing Mount-Point Errors)

## After a clean reinstall, the most annoying issues are usually LXC startup failures. You restore from backup, click Start, and it dies with a generic error.

### Typical startup log:

```
lxc.hook.pre-start: ... failed to run
__lxc_start: ... failed to initialize
startup for container '10X' failed
```


In almost every case, this points to a failed storage mount point. We’ve seen two primary causes.

## Cause 1 — “Ghost” Mount Points

Backups preserve not only data but also the container config (e.g., 101.conf), which includes references to old disk mounts.

### Problem
Your new host may use different paths (e.g., /mnt/disco8tb) or you may have stale mpX entries that no longer exist. LXC tries to mount those paths and fails.

Inspect the config (replace 101 with your CT ID):

```bash
cat /etc/pve/lxc/101.conf
```


You’ll see something like:

```
# OK: root disk on storage
rootfs: DataStore01:101/vm-101-disk-1.raw,size=8G

# BAD: stale mounts from the old host
mp0: /mnt/backup8tb/media,mp=/media
mp1: /mnt/disco8tb,mp=/media/storage
```

### Fix (delete ghost mounts):

```bash
pct set 101 --delete mp0
pct set 101 --delete mp1
```


Try starting the container again. If it boots, re-add the correct mount points via the Proxmox GUI (Hardware → Add → Mount Point).

## Cause 2 — The ntfs Filesystem Trap

If your external disks (e.g., that 8 TB drive) are formatted as ntfs for Windows compatibility, you’ll likely hit permission mapping issues.

### Problem
Linux can read NTFS, but its permission model doesn’t map cleanly to LXC. Even privileged containers can fail the pre-start hook when the host mount doesn’t expose owners/permissions in a usable way.

### Fix — mount NTFS with permissive options on the host

1. Install the proper driver:

    ```bash
    sudo apt install ntfs-3g -y
    ```

2. Find your disk’s UUID:

    ```bash
    sudo blkid
    # Example output snippet:
    # /dev/sdb2: UUID="1A04B4DE04B4BE57" TYPE="ntfs" ...
    ```

3. Create the mount point (if needed) and make it persistent in fstab:

    ```bash
    sudo mkdir -p /mnt/disco8tb
    sudo nano /etc/fstab
    ```

4. Add the line (replace with your UUID and mount path):

    ```
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

## Helpful Tips
- Always ensure your backups are up-to-date before making changes.
- Document any changes made to system configurations for future reference.
- If unsure about a command, consult the man pages or seek assistance.

## Quotation Block for Important Notes
> **Note:** It's crucial to understand each step and command used in this guide. Misconfigurations can lead to system instability or data loss. Always proceed with caution and seek expert advice if needed.

# 🤖 Automation Kit — How it works

> A short explainer of the scripts and workflows that validate, stage, sync and alert on your Proxmox backups.

## Table of contents

- [sync_lxc_backups.sh — Core logic](#sync_lxc_backupssh---core-logic)
- [backup_host.sh & check_disk.sh — Helpers](#backup_hostsh--check_disksh---helpers)
- [n8n alerting workflows](#n8n-alerting-workflows)
- [Telegram formatting gotchas & fixes](#telegram-formatting-gotchas--fixes)
- [Guarantees & behavior](#guarantees--behavior)

---

## sync_lxc_backups.sh — Core logic

This script does more than copy files. It's designed to prevent bad uploads and accidental data loss by using a staging area and two verification steps before any file is promoted to the cloud sync target.

### a) Staging (safety net)

- Keeps a `cloud_staging/` folder with the latest known-good backup for each LXC.
- If today's backup is corrupt, the previous good copy remains in staging. This prevents uploading or deleting your last good backup.

### b) Verification (two checks before staging)

- Log check: scans the newest `.log` for `ERROR:` to detect backup creation failures.
- Integrity check: runs `zstd -t` on the newest `.tar.zst` to ensure it's decompressible.

If either check fails, the script skips staging that container and leaves the prior valid file in place.

### c) Alerting (fail fast, skip safely)

- On verification failure the script POSTs a detailed JSON payload to an n8n webhook so you get a readable alert and the failing container is skipped.

### d) Cloud sync (incremental & fast)

- Uses `rclone sync` to mirror `cloud_staging/` to the configured remote (e.g., `gdrive:`). Only changed or new files transfer.

### e) Trash cleanup (quota-friendly)

- After a successful sync the script runs `rclone cleanup` to empty the cloud trash and help conserve limited Drive quota.

## backup_host.sh & check_disk.sh — Helpers

- `backup_host.sh` — creates a `.tar.gz` snapshot of `/etc` and `/root` (captures network config, `fstab`, `sshd_config`, and the scripts). Keep this archive as the host's configuration brain.
- `check_disk.sh` — checks disk usage with `df`; if usage > `THRESHOLD` (e.g., `90%`) it POSTs an alert to n8n so you can address storage pressure before backups fail.

## n8n alerting workflows

The scripts POST JSON payloads to n8n webhooks; n8n evaluates simple IF logic and sends clear Telegram messages.

Example payload (from `lxc_backup_alerts.json`):

```json
{
  "status": "exito",
  "success_count": 12,
  "fail_count": 1,
  "fail_reasons": "LXC-107: zstd integrity check failed"
}
```

n8n IF node logic:

- If `fail_count > 0` → send “Success with Failures” (include `fail_reasons`).
- Else → send “Total Success.”

## Telegram formatting gotchas & fixes

Problem: Telegram's Markdown parser is brittle. Filenames with underscores, dashes or other characters commonly used in backup names (for example `vzdump-lxc-107_2025...`) often trigger "can't parse entities" errors.

Fixes applied in all Telegram nodes:

- Set Parse Mode to `HTML` (more predictable than Markdown).
- Use `<b>` for bold and `<pre>...</pre>` to wrap raw error lists or filenames so Telegram won't try to parse them.

Example template used in Telegram nodes:

```html
<b>Status:</b> {{ $json.body.status }}<br/>
<b>Succeeded:</b> {{ $json.body.success_count }}<br/>
<b>Failed:</b> {{ $json.body.fail_count }}<br/>
<b>Reasons:</b>
<pre>{{ $json.body.fail_reasons }}</pre>
```

## Guarantees & behavior

- Never overwrite the last known-good backup with a bad one.
- Idempotent: safe to run daily or re-run manually.
- Sends clear, actionable alerts via n8n/Telegram when a problem occurs.

---

If you'd like, I can also:

- Add example `rclone` remote and `fstab` snippets
- Produce a small `.env.example` to centralize variables used by the scripts
- Add a short troubleshooting checklist for common failure modes
