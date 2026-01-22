#!/bin/bash
# LXC Identity Reset (Run inside a CLONED container)
if [ "$EUID" -ne 0 ]; then echo "Please run as root"; exit 1; fi

echo ">> 1. Resetting Machine ID..."
rm -f /etc/machine-id /var/lib/dbus/machine-id
dbus-uuidgen --ensure=/etc/machine-id
dbus-uuidgen --ensure

echo ">> 2. Regenerating SSH Host Keys..."
rm -fv /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

echo ">> 3. Cleaning logs..."
truncate -s 0 /var/log/syslog 2>/dev/null
truncate -s 0 /var/log/auth.log 2>/dev/null

echo ">> Done! New ID generated. Please REBOOT this container."
