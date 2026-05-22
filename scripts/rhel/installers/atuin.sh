#!/usr/bin/env bash

source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

initialize_atuin() {
    echo_with_color "$YELLOW_COLOR" "Initializing atuin..."
    add_to_path "$HOME/.atuin/bin"
}

update_bashrc() {
    local bashrc_file="$HOME/.bashrc"
    echo_with_color "$GREEN" "Updating $bashrc_file..."
    add_line_to_file "export PATH=\"\$HOME/.atuin/bin:\$PATH\"" "$bashrc_file"
}


login_to_atuin() {
    if atuin status &> /dev/null; then
        if atuin status | grep -q "cannot show sync status"; then
            echo_with_color "$YELLOW_COLOR" "atuin is not logged in."
            if atuin login -u "$ATUIN_USER"; then
                echo_with_color "$GREEN_COLOR" "atuin login successful."
            else
                echo_with_color "$RED_COLOR" "atuin login failed."
                exit_with_error "Failed to log in to atuin with user $ATUIN_USER." 2
            fi
        else
            echo_with_color "$GREEN_COLOR" "atuin is already logged in."
        fi
    else
        echo_with_color "$RED_COLOR" "Unable to determine atuin status. Please check atuin configuration."
        exit_with_error "Unable to determine atuin status." 1
    fi
}

install_atuin_with_script() {
    # Must be first in the .bashrc file to ensure that the atuin binary is available in the PATH else command not found error will occur.
    update_bashrc
    echo_with_color "$YELLOW_COLOR" "Installing atuin with the atuin script..."
    if bash <(curl -sS https://raw.githubusercontent.com/ellie/atuin/main/install.sh); then
        echo_with_color "$GREEN_COLOR" "atuin installed successfully."
        initialize_atuin
        login_to_atuin
    else
        echo_with_color "$RED_COLOR" "Failed to install atuin."
        exit_with_error "Failed to install atuin with the script." 1
    fi
}

if ! command_exists curl; then
    exit_with_error "The curl command is required to install atuin but it's not installed."
fi

if ! command_exists atuin; then
    install_atuin_with_script
else
    echo_with_color "$YELLOW_COLOR" "atuin is already installed."
fi