#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

PYTHON_VERSIONS=("3.13" "3.12" "3.11")

install_uv() {
    msg_info "Installing uv..."
    if command_exists curl; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
    elif command_exists wget; then
        wget -qO- https://astral.sh/uv/install.sh | sh
    else
        handle_error "curl or wget is required to install uv. Please install curl or wget and try again."
        exit 1
    fi
}

install_python_versions() {
    export PATH="${HOME}/.local/bin:$PATH"
    if ! command_exists uv; then
        handle_error "uv did not install. Please run check why and try again."
        exit 1
    fi

    msg_info "Installing Python versions with uv..."
    for version in "${PYTHON_VERSIONS[@]}"; do
        msg_info "Installing Python $version..."
        if uv python install "$version"; then
            msg_ok "Python $version installed successfully."
        else
            handle_error "Failed to install Python $version with uv."
        fi
    done
}

main() {
    if ! command_exists uv; then
        install_uv
    else
        msg_ok "uv is already installed."
    fi

    install_python_versions
}

main "$@"
