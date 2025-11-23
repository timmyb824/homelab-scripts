#!/usr/bin/env bash

source "../../init/init.sh"

MOUNT_POINT="/mnt/bryantnas"
NAS_IP="192.168.86.44"
NAS_SHARE="/volume1/homelab"
EXPECTED_USER="$USER"

# Function to add the NFS mount to /etc/fstab
add_to_fstab() {
    FSTAB_ENTRY="$NAS_IP:$NAS_SHARE $MOUNT_POINT nfs defaults 0 0"
    if ! grep -qs "$FSTAB_ENTRY" /etc/fstab; then
        echo_with_color "$BLUE_COLOR" "Adding NFS share to /etc/fstab..."
        if ! echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab; then
            exit_with_error "Failed to add NFS share to /etc/fstab."
        fi
        echo_with_color "$GREEN_COLOR" "Successfully added NFS share to /etc/fstab."
    else
        echo_with_color "$GREEN_COLOR" "NFS share is already present in /etc/fstab."
    fi
}

# Check if we can cd into the directory or if it is not empty
if [ -d "$MOUNT_POINT" ] && cd "$MOUNT_POINT" && [ "$(ls -A "$MOUNT_POINT")" ]; then
    echo_with_color "$BLUE_COLOR" "$MOUNT_POINT is already mounted and accessible."
    exit 0
fi

echo_with_color "$BLUE_COLOR" "UPDATE SHARED FOLDER RULE WITH IP OF THE VM IN THE SYNOLOGY NAS OR THIS WILL FAIL."

echo_with_color "$BLUE_COLOR" "Installing nfs-common if not already installed..."
if ! dpkg -l | grep -qw nfs-common; then
    if ! sudo apt update || ! sudo apt install -y nfs-common; then
        exit_with_error "Failed to install nfs-common."
    fi
    echo_with_color "$GREEN_COLOR" "Successfully installed nfs-common."
else
    echo_with_color "$GREEN_COLOR" "nfs-common is already installed."
fi

echo_with_color "$BLUE_COLOR" "Creating mount directory $MOUNT_POINT..."
if ! sudo mkdir -p "$MOUNT_POINT"; then
    exit_with_error "Failed to create mount directory $MOUNT_POINT."
fi
echo_with_color "$GREEN_COLOR" "Successfully created mount directory $MOUNT_POINT."

echo_with_color "$BLUE_COLOR" "Mounting NFS share $NAS_SHARE from $NAS_IP to $MOUNT_POINT..."
if ! sudo mount -t nfs -o vers=4 "$NAS_IP:$NAS_SHARE" "$MOUNT_POINT"; then
    exit_with_error "Failed to mount the NFS share $NAS_SHARE from $NAS_IP."
fi
echo_with_color "$GREEN_COLOR" "Successfully mounted the NFS share $NAS_SHARE from $NAS_IP."

echo_with_color "$BLUE_COLOR" "Setting permissions for $MOUNT_POINT..."
# Only change the permissions of the folders
if ! sudo find "$MOUNT_POINT" -type d -exec chown "$EXPECTED_USER:$EXPECTED_USER" {} +; then
    exit_with_error "Failed to set permissions for $MOUNT_POINT."
fi
echo_with_color "$GREEN_COLOR" "Successfully set permissions for $MOUNT_POINT."

# Add the NFS mount to /etc/fstab to make it persistent
add_to_fstab

echo_with_color "$GREEN_COLOR" "Successfully mounted NFS share from BryantNAS."
