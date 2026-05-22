#!/usr/bin/env bash

source "../../init/init.sh"


# Function to handle errors and revert changes
handle_error() {
  echo "An error occurred. Reverting changes..."
  if [[ -d "/usr/local/bin/backup_prometheus_${CURRENT_VERSION}" ]]; then
    mv /usr/local/bin/backup_prometheus_${CURRENT_VERSION}/* /usr/local/bin/
    rmdir /usr/local/bin/backup_prometheus_${CURRENT_VERSION}
    echo "Restored old Prometheus binaries."
  fi
  systemctl start prometheus
  exit 1
}

# Function to make a backup of current binaries
backup_binaries() {
  msg_info "Backing up current Prometheus binaries"
  mkdir -p /usr/local/bin/backup_prometheus_${CURRENT_VERSION}
  cp /usr/local/bin/prometheus /usr/local/bin/backup_prometheus_${CURRENT_VERSION}/ || {
    echo "Failed to backup prometheus binary. Cleaning up."
    rm -rf /usr/local/bin/backup_prometheus_${CURRENT_VERSION}
    return 1
  }
  cp /usr/local/bin/promtool /usr/local/bin/backup_prometheus_${CURRENT_VERSION}/ || {
    echo "Failed to backup promtool binary. Cleaning up."
    rm -rf /usr/local/bin/backup_prometheus_${CURRENT_VERSION}
    return 1
  }
  msg_ok "Backed up current Prometheus binaries to /usr/local/bin/backup_prometheus_${CURRENT_VERSION}"
}

# Trap any error to call the handle_error function
trap handle_error ERR

# Check if the script is being run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Please run with sudo or as root."
  exit 1
fi

# Update the OS package index
msg_info "Updating OS package index"
apt-get update || handle_error
msg_ok "Updated OS package index"

# Install required dependencies
msg_info "Installing Dependencies"
apt-get install -y curl sudo mc || handle_error
msg_ok "Installed Dependencies"

# Get the current version of Prometheus
CURRENT_VERSION=$(prometheus --version 2>&1 | head -n 1 | awk '{print $3}')

# Get the latest version of Prometheus
msg_info "Checking for the latest version of Prometheus"
LATEST_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }') || handle_error
msg_ok "Latest version of Prometheus is ${LATEST_VERSION}"

# Compare versions and update if a newer version is available
if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
  msg_ok "Prometheus is already up to date (version ${CURRENT_VERSION})"
  exit 0
fi

msg_info "A newer version of Prometheus is available (current: ${CURRENT_VERSION}, latest: ${LATEST_VERSION}). Proceeding with update."

# Backup current Prometheus binaries
systemctl stop prometheus || handle_error
backup_binaries || exit 1

# Update Prometheus
msg_info "Updating Prometheus to version ${LATEST_VERSION}"
mkdir -p /tmp/prometheus_update
cd /tmp/prometheus_update || handle_error
wget https://github.com/prometheus/prometheus/releases/download/v${LATEST_VERSION}/prometheus-${LATEST_VERSION}.linux-amd64.tar.gz || handle_error
tar -xvf prometheus-${LATEST_VERSION}.linux-amd64.tar.gz || handle_error
cd prometheus-${LATEST_VERSION}.linux-amd64 || handle_error

msg_info "Replacing old binaries with new ones"
mv prometheus promtool /usr/local/bin/ || handle_error
msg_ok "Replaced old binaries with new ones"

# Restart Prometheus service
msg_info "Restarting Prometheus service"
systemctl start prometheus || handle_error
msg_ok "Prometheus service restarted"

# Check if the update was successful
INSTALLED_VERSION=$(prometheus --version 2>&1 | head -n 1 | awk '{print $3}')
if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
  msg_ok "Prometheus updated successfully to version ${LATEST_VERSION}"
  exit 0
else
  msg_error "Failed to update Prometheus to version ${LATEST_VERSION}"
  exit 1
fi

# Clean up
msg_info "Cleaning up"
rm -rf /tmp/prometheus_update
msg_ok "Cleaned up"

msg_ok "Prometheus updated successfully to version ${LATEST_VERSION}"