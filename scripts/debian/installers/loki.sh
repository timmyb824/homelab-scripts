#!/usr/bin/env bash

source "../../init/init.sh"

set -eu

# # Function to handle errors and cleanup
# handle_error() {
#   msg_error "An error occurred. Exiting script."
#   cleanup
#   exit 1
# }

# # Function to perform any necessary cleanup
# cleanup() {
#   # Add any cleanup tasks here
#   rm -f /tmp/loki_install_tempfile || true
# }

# Trap any error to call the handle_error function
# trap handle_error ERR

LOKI_CONFIG_FILE="/etc/loki/config.yml"

# Function to install required dependencies
install_dependencies() {
  msg_info "Installing dependencies"
  sudo apt-get install -y wget || {
    msg_error "Failed to install dependencies"
    exit 1
  }
}

# Function to add the Grafana repository
add_grafana_repo() {
  msg_info "Adding Grafana repository"
  mkdir -p /etc/apt/keyrings/
  wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg || {
    msg_error "Failed to download Grafana GPG key"
    exit 1
  }
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list || {
    msg_error "Failed to add Grafana repository"
    exit 1
  }
}

# Function to install Loki
install_loki() {
  msg_info "Installing Loki"
  sudo apt-get update || {
    msg_error "Failed to update package lists"
    exit 1
  }
  sudo apt-get install -y loki || {
    msg_error "Failed to install Loki"
    exit 1
  }
  msg_ok "Installed Loki"
}

configure_loki(){
  msg_info "Configuring Loki"
  sudo tee $LOKI_CONFIG_FILE > /dev/null <<EOL
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

analytics:
  reporting_enabled: false

# CUSTOM
limits_config:
  # enforce_metric_name: false
  # reject_old_samples: true
  # reject_old_samples_max_age: 168h
  # max_cache_freshness_per_query: 10m
  # split_queries_by_interval: 15m
  # ingestion_burst_size_mb: 1000
  # ingestion_rate_mb: 10000
  # for big logs tune
  per_stream_rate_limit: 512M
  per_stream_rate_limit_burst: 1024M
  max_entries_limit_per_query: 1000000
  max_label_value_length: 20480
  max_label_name_length: 10240
  max_label_names_per_series: 300

EOL
  msg_ok "Configured Loki"
}

# Function to start Loki
start_loki() {
  msg_info "Starting Loki"
  sudo systemctl daemon-reload || {
    msg_error "Failed to reload systemd daemon"
    exit 1
  }
  sudo systemctl start loki || {
    msg_error "Failed to start Loki"
    exit 1
  }
  msg_ok "Started Loki"
}

# Main script logic
main() {
  if ! command -v loki &> /dev/null; then
    msg_info "Loki is not installed. Proceeding with installation."
    install_dependencies
    add_grafana_repo
    install_loki
    configure_loki
    start_loki
  else
    msg_ok "Loki is already installed"
  fi
}

# Run the main function
main

# Perform any necessary cleanup
# cleanup
