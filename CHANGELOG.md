# Changelog

All notable changes to this project will be documented in this file.

The format is based on **Keep a Changelog**  
and this project adheres to **Semantic Versioning** (SemVer).

---

## [v1.0.0] — 2025-11-12 — “Resilience”

This version marks the transition from a failed Proxmox host to a robust, automated, and continuously monitored production system.

### 🏥 Host Recovery & Stability (Critical Patch)

Critical fixes were implemented to recover the server from an unrecoverable state and ensure long-term operational stability.

- **Boot Recovery:** An unrecoverable boot failure (`Loading initial ramdisk...`) was diagnosed. A **clean Proxmox VE reinstall** (using `chroot` from an Ubuntu Live USB) was performed after repair attempts failed (`update-initramfs`, `proxmox-boot-tool`).
- **Network Fix (Host):** Removed an IP conflict that caused DHCP to override settings by configuring a **static IP** for `vmbr0` in `/etc/network/interfaces`.
- **Cron PATH Fix:** Solved script failures in `cron` (commands like `pct` or `ionice` not found) by adding a global `PATH` variable to crontab (`PATH=/usr/local/sbin:/usr/local/bin...`).
- **LXC Mount-Point Fix:** Resolved the critical `lxc.hook.pre-start` error preventing containers from starting:
  - Removed “ghost mounts” (`mpX`) using `pct set <vmid> --delete mpX`.
  - Corrected `/etc/fstab` for stable **NTFS** mounting using `ntfs-3g` and `rw,allow_other`.

### 🛡️ Resilience Scripts (New Capabilities)

Three scripts were created and refactored to **production-grade level**  
`sync_lxc_backups.sh`, `backup_host.sh`, `check_disk.sh`:

- **Persistent Logging:** All scripts now write to dedicated log files (e.g., `/mnt/disco8tb/logs/`) via a `log()` helper using `tee -a $LOG_FILE`.
- **Concurrency Locking (`flock`):** Prevents overlapping cron runs (`exec 9>/var/lock/script.lock`).
- **Error Capture (`trap`):** Added `trap _on_error ERR` and `trap _on_term INT TERM` to catch unexpected failures, log them, and send an n8n “fail” alert.
- **Preflight Checks:** Scripts verify required binaries (`rclone`, `zstd`, `pct`) and writable directories before running.
- **Test/Dry Mode (`DRYRUN`):** Added `DRYRUN=1` to simulate operations safely (e.g., `rclone --dry-run`).
- **Hardened JSON Payloads:** Implemented `json_escape` to guarantee valid JSON before sending failure reasons.
- **Cron Optimization:** Added `ionice -c 3` and `nice -n 19` to the backup sync task to minimize impact on the host.

### 💾 Backup Logic Enhancements (`sync_lxc_backups.sh` v4.7)

The LXC backup engine now includes robust protection mechanisms:

- **Strict 5-Step Verification:**
  1. `wait_stable_size` — Ensures file size stops changing before processing.
  2. `.log` file existence check.
  3. `grep -qi "ERROR:"` — Ensures the log has no errors.
  4. `grep -Eqi "INFO:.*finished"` — Confirms a successful backup.
  5. `zstd -t -T0` — Multi-threaded integrity test.
- **Staging Logic:** Valid backups are copied to `cloud_staging/`.  
  The script **never deletes the last known-good copy** if today’s backup fails.
- **Quota Management:** Uses `--drive-use-trash=false` to permanently delete old cloud files and avoid filling the Google Drive trash.
- **Remote Auto-Creation:** Automatically runs `rclone mkdir` if the Google Drive folder doesn’t exist.

### 📡 Alerts & Monitoring (n8n)

A full monitoring system was implemented in n8n:

- **Standardized Workflows:** Three workflows were created:
  - `lxc_backup_alerts`
  - `host_backup_alert`
  - `disk_alert`
- **Correct IF Logic:** `fail_count` is properly evaluated as a **Number**, ensuring accurate branching between “Total Success” and “Success with Failures.”
- **Telegram Formatting Fix:** Solved the `400 Bad Request: can't parse entities` issue:
  1. Switched Parse Mode to **HTML**
  2. Used `<b>` for bold
  3. Wrapped error lists in `<pre>...</pre>` to prevent Markdown misinterpretation

### 🧑‍💻 Development Environment

- **Centralized IDE:** Installed and configured **`code-server`** (VS Code in the browser) inside a dedicated LXC.
- **Secure Access:** Exposed via **Nginx Proxy Manager** with a subdomain, SSL (Let’s Encrypt), and WebSocket support.

### 📂 Project Management Improvements (GitHub)

Two GitHub repositories were created to standardize the project structure:

#### `Resilient_Proxmox_ReProxm`

- Uploaded anonymized versions of the 3 Bash scripts (v4.x / v2.x)
- Uploaded the 3 n8n workflows (`.json`)
- Added a robust `install.sh` automator (copy, placeholder replacement, crontab)
- Created detailed `README.md` (English) and `README-es.md` (Spanish)
- Added bilingual `ISSUE_TEMPLATE`s for bugs and enhancements

#### `gh-issue-importer`

- Created a PowerShell + `gh` CLI tool to bulk-import issues from a JSON file  
  (replacing fragile CSV imports)
- Includes a guardrail that auto-creates missing labels
- Imported a backlog of ~40 bilingual issues
