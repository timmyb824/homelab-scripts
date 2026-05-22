#!/usr/bin/env bash

source "../../init/init.sh"

# Function to install dependencies and set up repository
setup_repository() {
    msg_info "Setting up Grafana repository..."
    wget -q -O gpg.key https://rpm.grafana.com/gpg.key
    sudo rpm --import gpg.key
    echo -e '[grafana]\nname=grafana\nbaseurl=https://rpm.grafana.com\nrepo_gpgcheck=1\nenabled=1\ngpgcheck=1\ngpgkey=https://rpm.grafana.com/gpg.key\nsslverify=1\nsslcacert=/etc/pki/tls/certs/ca-bundle.crt' | sudo tee /etc/yum.repos.d/grafana.repo
}

# Function to install Alloy
install_alloy() {
    msg_info "Starting Alloy installation..."

    setup_repository

    msg_info "Updating package list and installing Alloy..."
    sudo yum update
    sudo dnf install -y alloy

    configure_alloy
}

# Function to update Alloy
update_alloy() {
    msg_info "Updating package list..."
    sudo yum update

    msg_info "Upgrading Alloy..."
    sudo dnf upgrade alloy

    restart_alloy
}

# Function to uninstall Alloy
uninstall_alloy() {
    msg_info "Stopping Alloy service..."
    sudo systemctl stop alloy

    msg_info "Disabling Alloy service..."
    sudo systemctl disable alloy

    msg_info "Removing Alloy package..."
    sudo dnf remove -y alloy

    msg_info "Removing Alloy configuration..."
    sudo rm -rf /etc/alloy

    msg_info "Cleaning up DNF..."
    sudo dnf autoremove -y

    msg_info "Removing Alloy ACLs..."
    sudo rm /etc/logrotate.d/Alloy_ACLs

    msg_ok "Alloy has been completely removed from the system."
}

handle_existing_promtail() {
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
            handle_error "No Promtail configuration file found at /etc/promtail/config.yaml or /etc/promtail/config.yml"
        fi

        msg_info "Stopping and disabling Promtail..."
        sudo systemctl stop promtail
        sudo systemctl disable promtail
    else
        msg_info "Promtail is not running"
    fi
}

# Function to configure Alloy
configure_alloy() {
    local LOKI_URL="$LOKI_URL"

    # Check if a LOKI_URL is provided
    if [ -z "$LOKI_URL" ]; then
        echo "LOKI_URL is not set."
        return 1
    fi

    sudo mkdir -p /etc/alloy

    sudo tee /etc/alloy/config.alloy >/dev/null <<EOF
local.file_match "system" {
  path_targets = [
    {
      __address__ = "localhost",
      __path__    = "/var/log/messages",
      job         = "syslog",
    },
    {
      __address__ = "localhost",
      __path__    = "/var/log/secure",
      job         = "syslog",
    },
    {
      __address__ = "localhost",
      __path__    = "/var/log/crowdsec.log",
      job         = "syslog",
    },
    {
      __address__ = "localhost",
      __path__    = "/var/log/crowdsec_api.log",
      job         = "syslog",
    },
    {
      __address__ = "localhost",
      __path__    = "/var/log/crowdsec-firewall-bouncer.log",
      job         = "syslog",
    },
  ]
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

// Uncomment this block only if /var/log/journal exists
// loki.source.journal "journal" {
//   max_age       = "12h0m0s",
//   path          = "/var/log/journal",
//   relabel_rules = discovery.relabel.journal.rules,
//   forward_to    = [loki.write.default.receiver],
//   labels = {
//     job = "systemd-journal",
//   },
// }

loki.write "default" {
    endpoint {
        url = "${LOKI_URL}"
    }
    external_labels = {
        host = "$(hostname)",
    }
}
EOF
}

set_alloy_acls() {
    local user="alloy"
    local group="alloy"
    local logrotate_conf="/etc/logrotate.d/Alloy_ACLs"

    msg_info "Setting ACLs and logrotate configuration for $user..."

    # Ensure the group exists
    if ! getent group "$group" >/dev/null; then
        sudo groupadd "$group" || {
            handle_error "Failed to create group $group"
        }
    fi

    # Add the user to the group
    sudo usermod -aG "$group" "$user" || {
        handle_error "Failed to add user $user to group $group"
    }

    # Set ACLs for the log files
    sudo setfacl -m g:$group:rx /var/log/cron
    sudo setfacl -m g:$group:rx /var/log/messages
    sudo setfacl -m g:$group:rx /var/log/secure
    sudo setfacl -m g:$group:rx /var/log/crowdsec.log
    sudo setfacl -m g:$group:rx /var/log/crowdsec_api.log
    sudo setfacl -m g:$group:rx /var/log/crowdsec-firewall-bouncer.log

    # Add logrotate configuration
    sudo tee "$logrotate_conf" >/dev/null <<EOL
{
    postrotate
        /usr/bin/setfacl -m g:$group:rx /var/log/cron
        /usr/bin/setfacl -m g:$group:rx /var/log/messages
        /usr/bin/setfacl -m g:$group:rx /var/log/secure
        /usr/bin/setfacl -m g:$group:rx /var/log/crowdsec.log
        /usr/bin/setfacl -m g:$group:rx /var/log/crowdsec_api.log
        /usr/bin/setfacl -m g:$group:rx /var/log/crowdsec-firewall-bouncer.log
    endscript
}
EOL

    msg_info "ACLs set and logrotate configuration added for $user."
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
    handle_existing_promtail
    set_alloy_acls
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
