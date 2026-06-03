#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "Error: this script must be run as root or with sudo"
   echo "Usage: sudo ./upgrade-archivebox.sh"
   exit 1
fi

echo "Upgrading ArchiveBox..."
sudo -u archivebox HOME=/opt/archivebox uv tool upgrade archivebox

echo "Restarting service..."
systemctl restart archivebox
systemctl status archivebox --no-pager
