#!/usr/bin/env bash

# Source necessary utilities
source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

# Function to install Promtail
install_promtail() {
    local version=$1
    local deb_file="promtail-${version}.aarch64.rpm"
    local download_url="https://github.com/grafana/loki/releases/download/v${version}/${deb_file}"

    echo_with_color "$GREEN" "Starting Promtail installation..."

    # Downloading Promtail .deb package
    echo_with_color "$GREEN" "Downloading Promtail version ${version}..."
    if ! wget "${download_url}" -O "${deb_file}" 2>/dev/null; then
        echo_with_color "$RED" "Failed to download Promtail .deb package"
        return 1
    fi
    echo_with_color "$GREEN" "Download complete."

    # Install the downloaded .deb package
    echo_with_color "$GREEN" "Installing Promtail..."
    if ! sudo yum install -y "${deb_file}"; then
        echo_with_color "$RED" "Failed to install Promtail"
    else
        echo_with_color "$GREEN" "Promtail installation completed successfully."
    fi

    # Cleanup downloaded package
    echo_with_color "$GREEN" "Cleaning up..."
    rm "${deb_file}"
    echo_with_color "$GREEN" "Cleanup complete."
}

create_promtail_user() {
    # check if promtail user exists and create it if it doesn't
    echo_with_color "$GREEN" "Checking for promtail user..."
    if ! id promtail &>/dev/null; then
        echo_with_color "$YELLOW" "Promtail user not found. Creating promtail user..."
        sudo useradd --system promtail || echo_with_color "$RED" "Failed to create promtail user."
    fi
    echo_with_color "$GREEN" "Promtail user found."
}

set_promtail_acls() {
    local user="promtail"
    local group="promtail"
    local logrotate_conf="/etc/logrotate.d/Promtail_ACLs"

    echo_with_color "$GREEN" "Setting ACLs and logrotate configuration for $user..."

    # Ensure the group exists
    if ! getent group "$group" >/dev/null; then
        sudo groupadd "$group" || {
            echo_with_color "$RED_COLOR" "Failed to create group $group"
            return 1
        }
    fi

    # Add the user to the group
    sudo usermod -aG "$group" "$user" || {
        echo_with_color "$RED_COLOR" "Failed to add user $user to group $group"
        return 1
    }

    # Set ACLs for the log files
    sudo setfacl -m g:$group:rx /var/log/cron
    sudo setfacl -m g:$group:rx /var/log/messages
    sudo setfacl -m g:$group:rx /var/log/secure
    sudo setfacl -m g:$group:rx /var/log/fail2ban.log

    # Add logrotate configuration
    sudo tee "$logrotate_conf" >/dev/null <<EOL
{
    postrotate
        /usr/bin/setfacl -m g:$group:rx /var/log/cron
        /usr/bin/setfacl -m g:$group:rx /var/log/messages
        /usr/bin/setfacl -m g:$group:rx /var/log/secure
        /usr/bin/setfacl -m g:$group:rx /var/log/fail2ban.log
    endscript
}
EOL

    echo_with_color "$GREEN_COLOR" "ACLs set and logrotate configuration added for $user."
}

configure_promtail() {
    local LOKI_URL=$1

    # Use your function echo_with_color if it's defined, or just echo otherwise
    if command -v echo_with_color &>/dev/null; then
        echo_with_color "$GREEN" "Configuring Promtail..."
    else
        echo "Configuring Promtail..."
    fi

    # Make a backup of the original Promtail config
    sudo cp /etc/promtail/config.yml /etc/promtail/config.yml.bak

    # Write the new Promtail configuration to the file
    sudo tee /etc/promtail/config.yml >/dev/null <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: ${LOKI_URL}
    external_labels:
      host: $(hostname)

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          __path__: /var/log/messages

  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          __path__: /var/log/secure

  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: fail2ban
          __path__: /var/log/fail2ban.log

EOF
}

upgrade_promtail() {
    local version=$1
    local deb_file="promtail-${version}.aarch64.rpm"
    local download_url="https://github.com/grafana/loki/releases/download/v${version}/${deb_file}"

    echo_with_color "$GREEN" "Starting Promtail upgrade..."

    # Downloading Promtail .deb package
    echo_with_color "$GREEN" "Downloading Promtail version ${version}..."
    if ! wget "${download_url}" -O "${deb_file}" 2>/dev/null; then
        echo_with_color "$RED" "Failed to download Promtail .deb package"
        return 1
    fi
    echo_with_color "$GREEN" "Download complete."

    # Install the downloaded .deb package
    echo_with_color "$GREEN" "Installing Promtail..."
    if ! sudo yum install -y "${deb_file}"; then
        echo_with_color "$RED" "Failed to install Promtail"
    else
        echo_with_color "$GREEN" "Promtail upgrade completed successfully."
    fi

    # Cleanup downloaded package
    echo_with_color "$GREEN" "Cleaning up..."
    rm "${deb_file}"
    echo_with_color "$GREEN" "Cleanup complete."
}

restart_promtail() {
    echo_with_color "$GREEN" "Restarting Promtail..."
    sudo systemctl daemon-reload || echo_with_color "$RED" "Failed to reload systemd."
    sudo systemctl restart promtail || echo_with_color "$RED" "Failed to restart Promtail."
    echo_with_color "$GREEN" "Promtail restarted."
}

install_podlet() {
    if ! command_exists podlet; then
        echo_with_color "$GREEN" "Installing Podlet..."
        if command_exists cargo; then
            cargo install podlet || echo_with_color "$RED" "Failed to install Podlet."
        else
            echo_with_color "$RED" "Cargo is not installed. Please install Rust and Cargo and try again."
        fi
    else
        echo_with_color "$GREEN" "Podlet is already installed."
    fi
}

if ! command_exists promtail; then
    install_promtail "$PROMTAIL_VERSION"
    create_promtail_user
    set_promtail_acls
    configure_promtail "http://logging.tailebee.ts.net:3100/loki/api/v1/push"
    restart_promtail
    install_podlet
else
    # check if the installed version is the same as the desired version
    if [ "$(promtail --version | grep 'promtail, version' | awk '{print $3}')" != "$PROMTAIL_VERSION" ]; then
        echo_with_color "$YELLOW" "Promtail is already installed but the version is different."
        upgrade_promtail "$PROMTAIL_VERSION"
        restart_promtail
    else
        echo_with_color "$GREEN" "Promtail is already installed and up-to-date."
    fi
fi
