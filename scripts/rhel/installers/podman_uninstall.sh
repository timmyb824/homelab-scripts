#!/usr/bin/env bash

# Source necessary utilities
source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

# Function to check if Podman is installed
check_podman_installed() {
    if command_exists podman; then
        return 0
    else
        echo_with_color "$GREEN_COLOR" "Podman is not installed."
        return 1
    fi
}

# Function to uninstall Podman
uninstall_podman() {
    # Remove Podman and its dependencies
    if ! sudo yum remove -y container-tools; then
        echo_with_color "$RED_COLOR" "Failed to remove Podman."
        return 1
    fi

    echo_with_color "$GREEN_COLOR" "Podman uninstalled successfully."

    # Remove podman-compose
    if command_exists uv; then
        if ! uv tool uninstall podman-compose; then
            echo_with_color "$RED_COLOR" "Failed to uninstall podman-compose."
            return 1
        fi
        echo_with_color "$GREEN_COLOR" "podman-compose uninstalled successfully."
    fi

    # Remove Podman configurations
    local config_dir="$HOME/.config/containers"
    if [[ -d "$config_dir" ]]; then
        if ! rm -rf "$config_dir"; then
            echo_with_color "$RED_COLOR" "Failed to remove Podnfiguration directory."
            return 1
        fi
        echo_with_color "$GREEN_COLOR" "Podman configuration directory removed successfully."
    fi

    # remove systemd user unit files (if uninstalling/reinstalling leaving these may help restart the containers)
    #    local systemd_dir="$HOME/.config/systemd"
    #    if [[ -d "$systemd_dir" ]]; then
    #      if ! rm -rf "$systemd_dir"; then
    #          echo_with_color "$RED_COLOR" "Failed to remove systemd user unit files."
    #          return 1
    #      fi
    #      echo_with_color "$GREEN_COLOR" "Systemd user unit files removed successfully."
    #    fi

    # Disable lingering for the user
    if ! sudo loginctl disable-linger "$USER"; then
        echo_with_color "$RED_COLOR" "Failed to disable lingering for user $USER."
        return 1
    fi
    echo_with_color "$GREEN_COLOR" "Lingering disabled for user $USER."

    # Remove sysctl configuration for privileged ports
    local sysctl_conf="/etc/sysctl.d/podman-privileged-ports.conf"
    if [[ -f "$sysctl_conf" ]]; then
        if ! sudo rm "$sysctl_conf"; then
            echo_with_color "$RED_COLOR" "Failed to remove sysctl configuration for privileged ports."
            return 1
        fi
        echo_with_color "$GREEN_COLOR" "Sysctl configuration for privileged ports removed successfully."
    fi

    # Symlink removal
    if [[ -L /var/run/docker.sock ]]; then
        if ! sudo rm /var/run/docker.sock; then
            echo_with_color "$RED_COLOR" "Failed to remove Docker symlink."
            return 1
        fi
        echo_with_color "$GREEN_COLOR" "Docker symlink removed successfully."
    fi

    echo_with_color "$GREEN_COLOR" "Podman and its configurations were completely uninstalled."
}

# Main script execution
if check_podman_installed; then
    echo_with_color "$YELLOW_COLOR" "Uninstalling Podman..."
    uninstall_podman
else
    echo_with_color "$GREEN_COLOR" "Podman is not installed. Nothing to do."
fi
