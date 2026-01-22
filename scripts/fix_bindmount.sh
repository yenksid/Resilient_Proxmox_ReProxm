#!/bin/bash
# LXC Bind Mount Fixer for Proxmox (Resilient Kit)
# Usage: ./fix_bindmount.sh --ctid <ID> --source <HOST_PATH> --target <LXC_PATH>

if [ "$#" -ne 6 ]; then
    echo "Usage: $0 --ctid <ID> --source <HOST_PATH> --target <LXC_PATH>"
    exit 1
fi

CTID=$2
SOURCE=$4
TARGET=$6
CONF_FILE="/etc/pve/lxc/${CTID}.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "Error: Config file for CT $CTID not found."
    exit 1
fi

echo ">> Fixing bind mount for CT $CTID..."
# Relative path logic for lxc.mount.entry
RELATIVE_TARGET=${TARGET#/}
ENTRY="lxc.mount.entry: $SOURCE $RELATIVE_TARGET none bind,create=dir 0 0"

if grep -q "$SOURCE $RELATIVE_TARGET" "$CONF_FILE"; then
    echo ">> Entry already exists. Skipping."
else
    echo "$ENTRY" >> "$CONF_FILE"
    echo ">> Added safe mount entry."
fi
echo ">> Done! Restart container $CTID to apply."
