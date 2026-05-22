#!/usr/bin/env bash

# Source necessary utilities
source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

# Function to uninstall Promtail
uninstall_promtail() {
    echo_with_color "$GREEN" "Starting Promtail uninstallation..."

    # Remove Promtail package
    echo_with_color "$GREEN" "Removing Promtail package..."
    if ! sudo yum remove -y promtail; then
        echo_with_color "$RED" "Failed to remove Promtail package"
        return 1
    fi
    echo_with_color "$GREEN" "Promtail package removed successfully."
}

remove_promtail_user() {
    echo_with_color "$GREEN" "Removing promtail user..."
    sudo userdel promtail || echo_with_color "$RED" "Failed to remove promtail user."
    echo_with_color "$GREEN" "Removed promtail user."
}

undo_promtail_acls() {
    local group="promtail"
    local logrotate_conf="/etc/logrotate.d/Promtail_ACLs"

    # Remove ACLs for the log files
    sudo setfacl -x g:$group /var/log/cron
    sudo setfacl -x g:$group /var/log/messages
    sudo setfacl -x g:$group /var/log/secure

    # Remove logrotate configuration
    if [ -f "$logrotate_conf" ]; then
        sudo rm -f "$logrotate_conf" || { echo_with_color "$RED_COLOR" "Failed to remove logrotate configuration $logrotate_conf"; return 1; }
    fi

    echo_with_color "$GREEN_COLOR" "ACLs removed and logrotate configuration deleted for $group."
}

stop_promtail() {
    echo_with_color "$GREEN" "Stopping Promtail service..."
    sudo systemctl stop promtail || echo_with_color "$RED" "Failed to stop Promtail service."
    echo_with_color "$GREEN" "Deleting Promtail service..."
    sudo rm -f /etc/systemd/system/promtail.service || echo_with_color "$RED" "Failed to delete Promtail service."
    echo_with_color "$GREEN" "Promtail service stopped and deleted."
}

cleanup_promtail() {
    echo_with_color "$GREEN" "Cleaning up Promtail-related files and directories..."
    # Remove Promtail-related files and directories if necessary
    sudo rm -rf /etc/promtail /var/lib/promtail /tmp/positions.yaml
    echo_with_color "$GREEN" "Cleanup complete."
}

# Check if Promtail is installed
if command_exists promtail; then
    # Stop Promtail service
    stop_promtail

    # Remove Promtail package
    uninstall_promtail

    # Remove promtail user from the adm group
    remove_promtail_user

    # Undo ACLs and logrotate configuration
    undo_promtail_acls

    # Cleanup Promtail-related files and directories
    cleanup_promtail
else
    echo_with_color "$YELLOW" "Promtail is not installed. Skipping uninstallation..."
fi

echo_with_color "$GREEN" "Undo script completed."