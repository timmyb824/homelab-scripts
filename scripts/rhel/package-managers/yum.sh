#!/usr/bin/env bash

source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

install_yum_packages() {
    echo_with_color "$CYAN_COLOR" "Installing yum packages..."

    sudo yum update -y || exit_with_error "Failed to update yum package list"

    while IFS= read -r package; do
        trimmed_package=$(echo "$package" | xargs)  # Trim whitespace from the package name
        if [ -n "$trimmed_package" ]; then  # Ensure the line is not empty
            if sudo yum install -y "$trimmed_package"; then
                echo_with_color "$GREEN_COLOR" "${trimmed_package} installed successfully"
            else
                exit_with_error "Failed to install ${trimmed_package}"
            fi
        fi
    done < <(get_package_list yum.list)
}

# Ensure yum is installed
if ! command_exists yum; then
    exit_with_error "yum is required to install packages. Please install yum to continue."
fi

install_yum_packages
