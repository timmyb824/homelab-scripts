#!/usr/bin/env bash

set -euo pipefail

# Source necessary utilities
source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

ACTION="install"
while [[ $# -gt 0 ]]; do
    case $1 in
    --upgrade | -u)
        ACTION="upgrade"
        shift
        ;;
    *)
        msg_error "Unknown option: $1"
        echo "Usage: $0 [--upgrade|-u]"
        exit 1
        ;;
    esac
done

# Function to check if Podman is installed
check_podman_installed() {
    if command_exists podman; then
        msg_warn "Podman is already installed."
        podman --version
        return 0
    else
        return 1
    fi
}

initialize_python_uv() {
    if command_exists uv; then
        msg_ok "uv is already installed."
        return
    fi

    export PATH="${HOME}/.local/bin:$PATH"
    if ! command_exists uv; then
        msg_warn "uv is not installed. Please run uv.sh first."
        exit_with_error "uv installation required"
    fi
}

# Function to install Podman
install_podman() {
    if ! sudo yum install -y container-tools; then
        exit_with_error "Failed to install Podman."
    fi

    if podman --version; then
        msg_ok "Podman has been installed successfully."
    else
        exit_with_error "Failed to install Podman."
    fi

    msg_warn "Configuring Podman..."

    local config_dir="$HOME/.config/containers"
    mkdir -p "$config_dir"

    if ! cp /etc/containers/registries.conf "$config_dir/"; then
        msg_error "Failed to copy registries.conf file to $config_dir."
        return 1
    fi

    local registry_line='unqualified-search-registries = ["docker.io","quay.io","container-registry.oracle.com","ghcr.io"]'
    if ! grep -Fxq "$registry_line" "$config_dir/registries.conf"; then
        if ! echo "$registry_line" >>"$config_dir/registries.conf"; then
            msg_error "Failed to add image registries to registry configuration."
            return 1
        fi
    else
        msg_info "Registry configuration already present in $config_dir/registries.conf"
    fi

    # Enable containers to run after logout
    if ! sudo loginctl enable-linger $(whoami); then
        handle_error "Failed to enable lingering for user $(whoami)."
    fi

    # Allow containers use of HTTP/HTTPS ports
    local sysctl_conf="/etc/sysctl.d/podman-privileged-ports.conf"
    local sysctl_line="net.ipv4.ip_unprivileged_port_start=80"
    if ! sudo grep -Fxq "$sysctl_line" "$sysctl_conf" 2>/dev/null; then
        sudo tee "$sysctl_conf" >/dev/null <<EOF
# Lowering privileged ports to allow us to run rootless Podman containers on lower ports
# From: www.smarthomebeginner.com
$sysctl_line
EOF
    else
        msg_info "$sysctl_conf already contains the required sysctl setting."
    fi

    if ! sudo sysctl --load "$sysctl_conf"; then
        handle_error "Failed to apply sysctl configuration for privileged ports."
    fi

    initialize_python_uv
    if ! uv tool install podman-compose; then
        handle_error "Failed to install podman-compose."
    fi

    msg_ok "Podman configuration completed successfully."
}

create_config_systemd_user_dir() {
    local config_dir="$HOME/.config/systemd/user"
    mkdir -p "$config_dir"
    msg_ok "Created systemd user directory at $config_dir."
}

symlink_podman_to_docker() {
    msg_warn "Symlinking Podman to Docker..."
    read -p "Do you want to symlink Podman to Docker? [y/N]: " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Creating the symlink..."
        if [ ! -S /run/podman/podman.sock ]; then
            handle_error "Podman socket does not exist. Please ensure Podman is installed and running."
        fi
        if [ -e /var/run/docker.sock ] || [ -L /var/run/docker.sock ]; then
            msg_warn "Docker socket already exists. Please remove or rename it before symlinking."
        fi
        if sudo ln -s /run/podman/podman.sock /var/run/docker.sock; then
            msg_ok "Podman symlinked to Docker successfully."
        else
            handle_error "Failed to symlink Podman to Docker."
        fi
    else
        msg_ok "Skipping symlink creation."
        return 0
    fi
}

upgrade_podman() {
    msg_info "Upgrading Podman..."
    if ! sudo yum upgrade -y container-tools; then
        handle_error "Failed to upgrade Podman."
    fi

    msg_info "Upgrading podman-compose..."
    initialize_python_uv
    if ! uv tool install podman-compose --upgrade; then
        handle_error "Failed to upgrade podman-compose."
    fi
}

# Main script execution
if [[ "$ACTION" == "install" ]]; then
    if check_podman_installed; then
        msg_warn "Skipping installation as Podman is already installed."
    else
        msg_info "Podman is not installed. Installing Podman..."
        install_podman
        create_config_systemd_user_dir
    fi
else
    if ! check_podman_installed; then
        handle_error "Podman is not installed. Please install it first."
    fi
    upgrade_podman
fi
