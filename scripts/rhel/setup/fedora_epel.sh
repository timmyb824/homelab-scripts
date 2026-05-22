#!/usr/bin/env bash

source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

echo_with_color "$YELLOW" "Updating yum..."
if sudo yum update -y; then
    echo_with_color "$GREEN" "System updated successfully."
else
    echo_with_color "$RED" "Failed to update the system."
fi


echo_with_color "$YELLOW" "Installing EPEL repository..."
if sudo yum install -y epel-release; then
    echo_with_color "$GREEN" "EPEL repository installed successfully."
else
    echo_with_color "$RED" "Failed to install EPEL repository."
fi


echo_with_color "$YELLOW" "Installing Fedora EPEL..."
if sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm; then
    echo_with_color "$GREEN" "Fedora EPEL installed successfully."
else
    echo_with_color "$RED" "Failed to install Fedora EPEL."
fi