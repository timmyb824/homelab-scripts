#!/usr/bin/env bash

source "../../init/init.sh"

# Function to install dependencies and set up repository
setup_repository() {
    msg_info "Installing dependencies..."
    sudo apt install -y gpg

    msg_info "Setting up Grafana repository..."
    sudo mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg >/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
}

# Function to install Alloy
install_alloy() {
    msg_info "Starting Alloy installation..."

    setup_repository

    msg_info "Updating package list and installing Alloy..."
    sudo apt-get update
    sudo apt install -y alloy

    configure_alloy
}

# Function to update Alloy
update_alloy() {
    msg_info "Updating package list..."
    sudo apt-get update

    msg_info "Upgrading Alloy..."
    sudo apt-get install --only-upgrade alloy

    restart_alloy
}

# Function to uninstall Alloy
uninstall_alloy() {
    msg_info "Stopping Alloy service..."
    sudo systemctl stop alloy

    msg_info "Disabling Alloy service..."
    sudo systemctl disable alloy

    msg_info "Removing Alloy package..."
    sudo apt remove -y alloy
    sudo apt purge -y alloy

    msg_info "Removing Alloy configuration..."
    sudo rm -rf /etc/alloy

    msg_info "Cleaning up APT..."
    sudo apt autoremove -y

    msg_ok "Alloy has been completely removed from the system."
}

# Function to configure Alloy
configure_alloy() {
    local LOKI_URL="$LOKI_URL"

    # Check if a LOKI_URL is provided
    if [ -z "$LOKI_URL" ]; then
        echo "LOKI_URL is not set."
        return 1
    fi

    msg_info "Checking Promtail status..."
    if systemctl is-active --quiet promtail; then
        msg_info "Promtail is running. Proceeding with configuration conversion..."

        if [ -f "/etc/alloy/config.alloy" ]; then
            msg_info "Backing up existing Alloy config..."
            sudo mv /etc/alloy/config.alloy /etc/alloy/config.alloy.orig
        fi

        # Check for both .yaml and .yml config files
        local promtail_config=""
        if [ -f "/etc/promtail/config.yaml" ]; then
            promtail_config="/etc/promtail/config.yaml"
        elif [ -f "/etc/promtail/config.yml" ]; then
            promtail_config="/etc/promtail/config.yml"
        else
            msg_error "No Promtail configuration file found at /etc/promtail/config.yaml or /etc/promtail/config.yml"
            return 1
        fi

        msg_info "Converting Promtail config to Alloy format..."
        sudo alloy convert --source-format=promtail --output=/etc/alloy/config.alloy "$promtail_config"

        msg_info "Stopping and disabling Promtail..."
        sudo systemctl stop promtail
        sudo systemctl disable promtail
    else
        msg_info "Promtail is not running. Creating new Alloy configuration..."

        sudo mkdir -p /etc/alloy

        sudo tee /etc/alloy/config.alloy >/dev/null <<EOF
local.file_match "system" {
    path_targets = [{
        __address__ = "localhost",
        __path__    = "/var/log/syslog",
        job         = "syslog",
    }]
}

loki.source.file "system" {
    targets               = local.file_match.system.targets
    forward_to            = [loki.write.default.receiver]
    legacy_positions_file = "/tmp/positions.yaml"
}

discovery.relabel "journal" {
    targets = []

    rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
    }
}

loki.source.journal "journal" {
    max_age       = "12h0m0s"
    path          = "/var/log/journal"
    relabel_rules = discovery.relabel.journal.rules
    forward_to    = [loki.write.default.receiver]
    labels        = {
        job = "systemd-journal",
    }
}

loki.write "default" {
    endpoint {
        url = "${LOKI_URL}"
    }
    external_labels = {
        host = "$(hostname)",
    }
}
EOF
    fi
}

# Function to restart Alloy
restart_alloy() {
    msg_info "Restarting Alloy service..."
    sudo systemctl restart alloy

    if systemctl is-active --quiet alloy; then
        msg_info "Alloy restarted successfully."
    else
        msg_error "Failed to restart Alloy. Check logs with: journalctl -u alloy"
        exit 1
    fi
}

# Function to start Alloy
start_alloy() {
    msg_info "Starting and enabling Alloy service..."
    sudo systemctl enable --now alloy

    if systemctl is-active --quiet alloy; then
        msg_info "Alloy started successfully."
        msg_ok "Alloy setup completed successfully!"
    else
        msg_error "Failed to start Alloy service. Check logs with: journalctl -u alloy"
        exit 1
    fi
}

# Main script execution
case "${1:-}" in
"install")
    install_alloy
    start_alloy
    ;;
"update")
    update_alloy
    ;;
"uninstall")
    uninstall_alloy
    ;;
*)
    msg_error "Usage: $0 {install|update|uninstall}"
    exit 1
    ;;
esac
