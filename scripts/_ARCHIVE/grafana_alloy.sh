#!/bin/bash

source "../../init/init.sh"

if [ "$EUID" -ne 0 ]; then
    handle_error "Please run as root (sudo)."
fi

# Installation function
install_alloy() {
    msg_info "Starting installation process..."

    msg_info "Installing gpg..."
    sudo apt install -y gpg || handle_error "Failed to install gpg."

    msg_info "Creating keyring directory..."
    sudo mkdir -p /etc/apt/keyrings/ || handle_error "Failed to create /etc/apt/keyrings/"

    log_message "Downloading Grafana GPG key..."
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg >/dev/null || handle_error "Failed to download or save Grafana GPG key."

    msg_info "Adding Grafana repository..."
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list >/dev/null || handle_error "Failed to add Grafana repository."

    msg_info "Updating package list..."
    sudo apt-get update || handle_error "Failed to update package list."

    msg_info "Installing alloy..."
    sudo apt-get install -y alloy || handle_error "Failed to install alloy."

    msg_ok "Alloy installation completed successfully."
}

# Uninstallation function
uninstall_alloy() {
    msg_info "Starting uninstallation process..."

    msg_info "Stopping alloy service..."
    sudo systemctl stop alloy || msg_warn "Failed to stop alloy service. It may not be running."

    msg_info "Removing alloy..."
    sudo apt-get remove -y alloy || handle_error "Failed to remove alloy."

    msg_info "Removing Grafana repository file..."
    sudo rm -i /etc/apt/sources.list.d/grafana.list || handle_error "Failed to remove Grafana repository file."

    msg_info "Reloading daemon..."
    sudo systemctl daemon-reload || handle_error "Failed to reload daemon."

    msg_ok "Alloy uninstallation completed successfully."
}

case "$1" in
install)
    install_alloy
    ;;
remove)
    uninstall_alloy
    ;;
*)
    msg_info "Usage: $0 {install|remove}"
    exit 1
    ;;
esac
