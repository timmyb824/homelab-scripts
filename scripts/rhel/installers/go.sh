#!/usr/bin/env bash

# Source necessary utilities
source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    handle_error "This script must be run as root"
fi

# Check if system is aarch64
if [[ $(uname -m) != "aarch64" ]]; then
    handle_error "This script is intended for aarch64 architecture only"
fi

# Set Go version
GO_VERSION="1.21.4"  # Update this as needed
INSTALL_DIR="/usr/local"
DOWNLOAD_URL="https://go.dev/dl/go${GO_VERSION}.linux-arm64.tar.gz"
TEMP_DIR=$(mktemp -d)

msg_info "Starting Go installation process..."
msg_info "Downloading Go version ${GO_VERSION}..."

# Download Go
if ! wget -q -P "$TEMP_DIR" "$DOWNLOAD_URL"; then
    handle_error "Failed to download Go"
fi

msg_ok "Download completed successfully"

# Remove any existing Go installation
if [ -d "${INSTALL_DIR}/go" ]; then
    msg_warn "Existing Go installation found. Removing..."
    rm -rf "${INSTALL_DIR}/go" || handle_error "Failed to remove existing Go installation"
fi

# Extract Go
msg_info "Extracting Go to ${INSTALL_DIR}..."
if ! tar -C "$INSTALL_DIR" -xzf "$TEMP_DIR/go${GO_VERSION}.linux-arm64.tar.gz"; then
    handle_error "Failed to extract Go"
fi

msg_ok "Go extracted successfully"

# Clean up temporary files
rm -rf "$TEMP_DIR"

# Setup environment variables
PROFILE_FILE="/etc/profile.d/go.sh"

msg_info "Setting up environment variables..."
cat > "$PROFILE_FILE" << EOF
export GOPATH=\$HOME/go
export PATH=\$PATH:${INSTALL_DIR}/go/bin
export PATH=\$PATH:\$HOME/go/bin
EOF

if [ ! -f "$PROFILE_FILE" ]; then
    handle_error "Failed to create profile file"
fi

chmod 644 "$PROFILE_FILE"

msg_ok "Environment variables set up successfully"

# Verify installation
source "$PROFILE_FILE"
GO_VERSION_OUTPUT=$(go version 2>&1)
if [[ $? -ne 0 ]]; then
    handle_error "Go installation verification failed"
fi

msg_ok "Go ${GO_VERSION} installed successfully!"
msg_info "Go version: ${GO_VERSION_OUTPUT}"
msg_info "Please log out and log back in for the environment variables to take effect"