#!/bin/bash

## Usage: ./update_hosts.sh --host host:port --host 123.23.23.44:22 --update --upgrade

# SSH User and Key File
ssh_user="remoter"
ssh_keyfile="~/.ssh/id_master_key"

# SSH Timeout (in seconds)
ssh_timeout=15

# Function to update apt repositories on a host
update_apt() {
    host="$1"
    echo -e "\nUpdating apt repositories on $host...\n"
    ssh -o StrictHostKeyChecking=no -i "$ssh_keyfile" -p "${host##*:}" -n -o ConnectTimeout="$ssh_timeout" "$ssh_user@${host%:*}" sudo apt-get update
    echo -e "\nApt update completed on $host."
}

# Function to upgrade packages on a host
upgrade_packages() {
    host="$1"
    echo -e "\nUpgrading packages on $host...\n"
    ssh -o StrictHostKeyChecking=no -i "$ssh_keyfile" -p "${host##*:}" -n -o ConnectTimeout="$ssh_timeout" "$ssh_user@${host%:*}" sudo apt-get upgrade -y
    echo -e "\n\nPackage upgrade completed on $host."
}

# Main script
hosts=()
update=false
upgrade=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            shift
            hosts+=("$1")
            shift
            ;;
        --update)
            shift
            update=true
            ;;
        --upgrade)
            shift
            upgrade=true
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if any hosts are specified
if [[ ${#hosts[@]} -eq 0 ]]; then
    echo "Please specify at least one host:port using --host."
    exit 1
fi

# Perform update and/or upgrade based on the parameters
for host in "${hosts[@]}"; do
    if [ "$update" = true ]; then
        update_apt "$host"
    fi

    if [ "$upgrade" = true ]; then
        upgrade_packages "$host"
    fi
done
