#!/usr/bin/env bash

# Source necessary utilities
source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

install_sops_oracle() {
    if command_exists sops; then
        msg_info "sops is already installed on Linux."
        return 0
    fi
    msg_info "Downloading sops binary for Linux..."
    SOPS_VERSION="3.9.1"
    SOPS_BINARY="sops-${SOPS_VERSION}-1.aarch64.rpm"
    SOPS_URL="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/${SOPS_BINARY}"
    msg_info "Downloading sops from: $SOPS_URL"

    if curl -LO "$SOPS_URL"; then
        if ! sudo dnf install -y "${SOPS_BINARY}"; then
            msg_error "Error: Failed to install sops from the downloaded file."
            return 1
        fi
        rm "$SOPS_BINARY"
        msg_ok "sops installed successfully on Linux."
    else
        msg_error "Error: Failed to download sops from the URL: $SOPS_URL"
        return 1
    fi
}

install_age_oracle() {
    if command_exists age; then
        msg_info "age is already installed on Linux."
        return 0
    fi

    GO_BIN="$(type -p go)"
    if ! command_exists "$GO_BIN"; then
        msg_error "Go is not installed. Please install Go and try again."
        return 1
    fi

    msg_info "Installing age with go..."
    if $GO_BIN install filippo.io/age/cmd/...@latest; then
        # Verify the installation
        if command_exists age; then
            msg_ok "age installed successfully on Linux."
        else
            msg_error "age binary not found in PATH after installation"
            return 1
        fi
    else
        msg_error "Error: Failed to install age with go."
        return 1
    fi
}

# Check if system is aarch64
if [[ $(uname -m) != "aarch64" ]]; then
    handle_error "This script is intended for aarch64 architecture only"
fi

install_sops_oracle
install_age_oracle
