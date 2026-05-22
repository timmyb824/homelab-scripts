#!/usr/bin/env bash

source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

# function to install rustup with error handling
install_rustup() {
    # Install rustup
    if ! command_exists rustup; then
        echo_with_color "$YELLOW_COLOR" "Installing rustup..."
        if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
            echo_with_color "$GREEN_COLOR" "rustup installed successfully."
        else
            exit_with_error "Failed to install rustup, please check the installation script."
        fi
    else
        echo_with_color "$GREEN_COLOR" "rustup is already installed."
        exit 0
    fi
}

initialize_cargo() {
    if command_exists cargo; then
        echo_with_color "$GREEN_COLOR" "cargo is already installed."
    else
        echo_with_color "$YELLOW_COLOR" "Initializing cargo..."
        if [ -f "$HOME/.cargo/env" ]; then
            source "$HOME/.cargo/env"
        else
            echo_with_color "$RED_COLOR" "Cargo environment file does not exist."
            exit_with_error "Please install cargo to continue."
        fi
    fi
}

# The is already done by the rustup installation script; leaving it here for reference
# update_bashrc() {
#     local bashrc_file="$HOME/.bashrc"
#     echo_with_color "$GREEN" "Updating $bashrc_file..."
#     echo "" >> "$bashrc_file"
#     add_line_to_file ". $HOME/.cargo/env" "$bashrc_file"
# }

if ! command_exists curl; then
    exit_with_error "curl is required to install rustup, please install curl first."
fi

install_rustup
initialize_cargo
# update_bashrc