#!/usr/bin/env bash
#
# refresh-grafana-key.sh
#
# Refresh the Grafana APT signing key and source list on Debian/Ubuntu
# without using apt-key (compatible with Debian 12 / Ubuntu 22.04+).

set -euo pipefail

KEYRING_DIR="/etc/apt/keyrings"
KEYRING="$KEYRING_DIR/grafana.gpg"
SOURCES_LIST="/etc/apt/sources.list.d/grafana.list"
REPO_LINE="deb [signed-by=$KEYRING] https://apt.grafana.com stable main"

echo "==> Refreshing Grafana APT key and repo"

# Create keyring directory if missing
sudo install -d -m 0755 "$KEYRING_DIR"

# Remove any legacy key files (optional safe cleanup)
sudo rm -f /etc/apt/trusted.gpg.d/grafana*.gpg || true

# Download and (re)install the current key (overwrite if needed)
echo "==> Downloading Grafana GPG key..."
curl -fsSL https://apt.grafana.com/gpg.key | sudo gpg --dearmor --yes -o "$KEYRING"

# Ensure correct permissions
sudo chmod 0644 "$KEYRING"

# Write/refresh the apt source list
echo "==> Writing source list entry..."
echo "$REPO_LINE" | sudo tee "$SOURCES_LIST" >/dev/null

# Update package metadata
echo "==> Running apt update..."
sudo apt update

echo "==> Grafana APT key and repo refreshed successfully."
