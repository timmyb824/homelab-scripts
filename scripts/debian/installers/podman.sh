#!/usr/bin/env bash

# Source necessary utilities
source "../../init/init.sh"

# Parse command line arguments
ACTION="install" # default action
while [[ $# -gt 0 ]]; do
    case $1 in
    --upgrade | -u)
        ACTION="upgrade"
        shift
        ;;
    *)
        echo_with_color "31" "Unknown option: $1"
        echo "Usage: $0 [--upgrade|-u]"
        exit 1
        ;;
    esac
done

# Function to check if Podman is installed
check_podman_installed() {
    if command_exists podman; then
        echo_with_color "32" "Podman is already installed."
        podman --version
        return 0
    else
        return 1
    fi
}

initialize_pip_linux() {
    if command_exists pip; then
        echo_with_color "$GREEN_COLOR" "pip is already installed."
        return
    fi

    local pip_path="$HOME/.pyenv/shims/pip"
    if [[ -x "$pip_path" ]]; then
        echo_with_color "$GREEN_COLOR" "Adding pyenv pip to PATH."
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        eval "$(pyenv init -)"
    else
        echo_with_color "$YELLOW_COLOR" "pip is not installed. Please run pyenv_python.sh first."
        exit_with_error "pip installation required"
    fi
}

# Function to install Podman
install_podman() {
    # Ensure sudo is available
    if ! command_exists sudo; then
        echo_with_color "31" "sudo command is required but not found. Please install sudo first."
        return 1
    fi

    # Instruction from: https://software.opensuse.org//download.html?project=devel%3Akubic%3Alibcontainers%3Aunstable&package=podman
    # Add the repository for Podman from the Kubic project
    if ! echo 'deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/unstable/xUbuntu_22.04/ /' | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:unstable.list; then
        echo "Failed to add the Podman repository to the sources list."
        return 1
    fi

    # Import the GPG key for the repository
    if ! curl -fsSL https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/xUbuntu_22.04/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/devel_kubic_libcontainers_unstable.gpg >/dev/null; then
        echo "Failed to import the GPG key for the Podman repository."
        return 1
    fi

    # Update the package database
    if ! sudo apt update; then
        echo "Failed to update the package database."
        return 1
    fi

    # Install Podman
    if ! sudo apt install -y podman podman-plugins; then
        echo "Failed to install Podman."
        return 1
    fi

    # Install podman-compose using pip
    if ! command_exists pip; then
        echo_with_color "31" "pip is not installed. Attempting to install pip..."
        initialize_pip_linux

    fi
    if ! pip install --user podman-compose; then
        echo_with_color "31" "Failed to install podman-compose."
        return 1
    fi

    echo_with_color "32" "Podman and podman-compose installed successfully."

    echo_with_color "33" "Configuring Podman..."

    local config_dir="$HOME/.config/containers"
    mkdir -p "$config_dir"

    if ! sudo cp /etc/containers/registries.conf "$config_dir/"; then
        echo_with_color "31" "Failed to copy registries.conf file to $config_dir."
        return 1
    fi

    if ! sudo chmod 777 "$config_dir/registries.conf"; then
        echo_with_color "31" "Failed to set permissions on $config_dir/registries.conf."
        return 1
    fi

    if ! echo "unqualified-search-registries = [\"docker.io\",\"quay.io\",\"container-registry.oracle.com\",\"ghcr.io\",\"lscr.io\"]" >>"$config_dir/registries.conf"; then
        echo_with_color "31" "Failed to add docker.io to registry configuration."
        return 1
    fi

    # Enable containers to run after logout
    if ! sudo loginctl enable-linger "$USER"; then
        echo_with_color "31" "Failed to enable lingering for user $USER."
        return 1
    fi

    # Allow containers use of HTTP/HTTPS ports
    local sysctl_conf="/etc/sysctl.d/podman-privileged-ports.conf"
    echo "# Lowering privileged ports to allow us to run rootless Podman containers on lower ports" | sudo tee "$sysctl_conf"
    echo "# From: www.smarthomebeginner.com" | sudo tee -a "$sysctl_conf"
    echo "net.ipv4.ip_unprivileged_port_start=80" | sudo tee -a "$sysctl_conf"

    if ! sudo sysctl --load "$sysctl_conf"; then
        echo_with_color "31" "Failed to apply sysctl configuration for privileged ports."
        return 1
    fi

    echo_with_color "31" "NOTE: May need to lower the privileged ports to 53 for DNS to work on some systems."
    echo_with_color "32" "Podman configuration completed successfully."
}

upgrade_podman() {
    echo_with_color "33" "Upgrading Podman..."

    # Initial system cleanup
    echo_with_color "33" "Performing initial system cleanup..."
    if ! sudo apt autoremove -y; then
        echo_with_color "31" "Failed to perform autoremove."
        return 1
    fi

    if ! sudo apt autoclean; then
        echo_with_color "31" "Failed to perform autoclean."
        return 1
    fi

    # Clean up old repository and key files
    echo_with_color "33" "Cleaning up old repository and key files..."
    sudo rm -f /etc/apt/sources.list.d/devel:kubic:libcontainers:unstable.list
    sudo rm -f /etc/apt/trusted.gpg.d/devel_kubic_libcontainers_unstable.gpg

    # Add the repository and key using more secure method
    echo_with_color "33" "Adding the repository and key using more secure method..."
    if ! curl -fsSL https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/xUbuntu_22.04/Release.key | sudo gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg; then
        echo_with_color "31" "Failed to import the GPG key."
        return 1
    fi

    if ! echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/unstable/xUbuntu_22.04/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:unstable.list; then
        echo_with_color "31" "Failed to add the Podman repository."
        return 1
    fi

    echo_with_color "33" "Updating package lists..."
    # Clean apt lists and update
    sudo rm -rf /var/lib/apt/lists/*
    sudo apt clean

    # Try update with a timeout
    if ! timeout 300 sudo apt update; then
        echo_with_color "31" "Failed to update package lists or operation timed out."
        echo_with_color "33" "Attempting additional cleanup..."
        sudo apt autoclean
        sudo apt clean
        if ! sudo apt update; then
            echo_with_color "31" "Update failed even after additional cleanup."
            return 1
        fi
    fi

    echo_with_color "33" "Upgrading Podman..."
    if ! sudo apt install --only-upgrade -y podman; then
        echo_with_color "31" "Failed to upgrade Podman."
        return 1
    fi

    echo_with_color "33" "Restarting Podman services..."
    # Restart rootless podman service
    systemctl --user daemon-reload
    systemctl --user restart podman.socket podman.service || true

    # Restart root podman service
    sudo systemctl daemon-reload
    sudo systemctl restart podman.socket podman.service || true

    # Wait a moment for services to fully restart
    sleep 5

    echo_with_color "33" "Upgrading podman-compose..."
    if command_exists pip; then
        if ! pip install --user --upgrade podman-compose; then
            echo_with_color "31" "Failed to upgrade podman-compose."
            return 1
        fi
    fi

    echo_with_color "32" "Podman upgrade completed successfully. New Version:"
    podman --version

    echo_with_color "33" "Verifying Podman socket API version..."
    if ! podman system info >/dev/null 2>&1; then
        echo_with_color "31" "Warning: Podman socket may not be running the latest version. You may need to log out and back in."
    fi
}

install_cni_plugin() {
    if [[ "$(lsb_release -cs)" == "jammy" ]]; then
        local cni_plugin_url="http://archive.ubuntu.com/ubuntu/pool/universe/g/golang-github-containernetworking-plugins/containernetworking-plugins_0.9.1+ds1-1ubuntu0.1_amd64.deb"
        local cni_plugin_deb="/tmp/containernetworking-plugins_0.9.1+ds1-1ubuntu0.1_amd64.deb"

        if ! wget -4 -O "$cni_plugin_deb" "$cni_plugin_url"; then
            echo_with_color "31" "Failed to download CNI plugin package."
            return 1
        fi

        if ! sudo dpkg -i "$cni_plugin_deb"; then
            echo_with_color "31" "Failed to install CNI plugin package."
            return 1
        fi

        echo_with_color "32" "CNI plugin package installed successfully."
    else
        echo_with_color "33" "Skipping CNI plugin installation as it is not supported on $(lsb_release -cs)."
    fi
}

create_config_systemd_user_dir() {
    local config_dir="$HOME/.config/systemd/user"
    mkdir -p "$config_dir"
    echo_with_color "32" "Created systemd user directory at $config_dir."
}

symlink_podman_to_docker() {
    echo_with_color "33" "Symlinking Podman to Docker..."
    read -p "Do you want to symlink Podman to Docker? [y/N]: " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Creating the symlink..."
        if [ ! -S /run/podman/podman.sock ]; then
            echo_with_color "31" "Podman socket does not exist. Please ensure Podman is installed and running."
            return 1
        fi
        if [ -e /var/run/docker.sock ] || [ -L /var/run/docker.sock ]; then
            echo_with_color "33" "Docker socket already exists. Please remove or rename it before symlinking."
            return 1
        fi
        if sudo ln -s /run/podman/podman.sock /var/run/docker.sock; then
            echo_with_color "32" "Podman symlinked to Docker successfully."
            return 0
        else
            echo_with_color "31" "Failed to symlink Podman to Docker."
            return 1
        fi
    else
        echo_with_color "32" "Skipping symlink creation."
        return 0
    fi
}

enable_and_start_rootless_podman_service() {
    echo_with_color "33" "Enabling and starting Podman service..."
    if ! systemctl --user enable --now podman.socket; then
        echo_with_color "31" "Failed to enable and start Podman service."
        return 1
    fi
    echo_with_color "32" "Podman service enabled and started successfully."
}

enable_and_start_root_podman_service() {
    echo_with_color "33" "Enabling and starting Podman service..."
    if ! sudo systemctl enable --now podman.socket; then
        echo_with_color "31" "Failed to enable and start Podman service."
        return 1
    fi
    echo_with_color "32" "Podman service enabled and started successfully."
}

# Main script execution
if [[ "$ACTION" == "upgrade" ]]; then
    if ! check_podman_installed; then
        echo_with_color "31" "Podman is not installed. Please install it first."
        exit 1
    fi
    upgrade_podman
else
    if check_podman_installed; then
        echo_with_color "32" "Skipping installation as Podman is already installed."
        echo_with_color "33" "Use --upgrade or -u option to upgrade Podman."
    else
        echo_with_color "33" "Installing Podman..."
        install_podman
        if [ $? -eq 0 ]; then
            install_cni_plugin
            create_config_systemd_user_dir
            symlink_podman_to_docker
            enable_and_start_rootless_podman_service
            enable_and_start_root_podman_service
            echo_with_color "32" "Podman installation and configuration completed successfully."
        fi
    fi
fi
