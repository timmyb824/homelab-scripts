#!/usr/bin/env bash

source "../../init/init.sh"

# Function to print informational messages
msg_info() {
  local msg="$1"
  echo -e "\033[1;34m[INFO] $msg\033[0m"
}

# Function to print success messages
msg_ok() {
  local msg="$1"
  echo -e "\033[1;32m[OK] $msg\033[0m"
}

# Function to print error messages
msg_err() {
  local msg="$1"
  echo -e "\033[1;31m[ERROR] $msg\033[0m"
}

# Check if the script is being run as root
if [[ $EUID -ne 0 ]]; then
  msg_err "This script must be run as root. Please run with sudo or as root."
  exit 1
fi

# Function to install required dependencies
install_dependencies() {
  msg_info "Installing dependencies"
  apt-get install -y wget || {
    msg_err "Failed to install dependencies"
    exit 1
  }
}

# Function to add the VirtualBox repository
add_virtualbox_repo() {
  msg_info "Adding VirtualBox repository"
  wget -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc | gpg --dearmor --yes --output /usr/share/keyrings/oracle-virtualbox-2016.gpg || {
    msg_err "Failed to add the VirtualBox repository"
    exit 1
  }
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] http://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib" | tee /etc/apt/sources.list.d/virtualbox.list || {
    msg_err "Failed to add the VirtualBox repository"
    exit 1
  }
}

# Function to install VirtualBox
install_virtualbox() {
  msg_info "Installing VirtualBox"
  apt-get update || {
    msg_err "Failed to update package lists"
    exit 1
  }
  apt-get install -y virtualbox-7.0 gcc-12 || {
    msg_err "Failed to install VirtualBox or gcc-12"
    exit 1
  }
  msg_ok "Installed VirtualBox"
}

run_vbox_config() {
  msg_info "Running VirtualBox configuration"
  /sbin/vboxconfig || {
    msg_err "Failed to run VirtualBox configuration. Try rebooting and running the remaining commands manually."
    exit 1
  }
  msg_ok "Ran VirtualBox configuration"
}

# Function to install the VirtualBox extensions pack
install_virtualbox_extensions_pack() {
  msg_info "Installing VirtualBox extensions pack"
  local vb_version

  vb_version=$(vboxmanage -v | cut -dr -f1)

  # need to make sure vb_version is a valid version number
  if [[ ! $vb_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    msg_err "Invalid VirtualBox version: $vb_version. Please check your VirtualBox installation."
    exit 1
  fi

  wget https://download.virtualbox.org/virtualbox/${vb_version}/Oracle_VM_VirtualBox_Extension_Pack-${vb_version}.vbox-extpack || {
    msg_err "Failed to download the VirtualBox extensions pack"
    exit 1
  }
  vboxmanage extpack install --replace Oracle_VM_VirtualBox_Extension_Pack-${vb_version}.vbox-extpack || {
    msg_err "Failed to install the VirtualBox extensions pack"
    exit 1
  }
  rm -f Oracle_VM_VirtualBox_Extension_Pack-${vb_version}.vbox-extpack
  msg_ok "Installed VirtualBox extensions pack"
}

add_user_to_vbox_group() {
  msg_info "Adding user to vbox group"
  usermod -aG vboxusers $SUDO_USER || {
    msg_err "Failed to add user to vbox group"
    exit 1
  }
  newgrp vboxusers || {
    msg_err "Failed to add user to vbox group"
    exit 1
  }
  msg_ok "Added user to vbox group"
}

add_vagrant_repo() {
  msg_info "Adding Vagrant repository"
  wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg || {
    msg_err "Failed to add the Vagrant repository"
    exit 1
  }
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list || {
    msg_err "Failed to add the Vagrant repository"
    exit 1
  }
}

install_vagrant() {
  msg_info "Installing Vagrant"
  apt-get update || {
    msg_err "Failed to update package lists"
    exit 1
  }
  apt-get install -y vagrant || {
    msg_err "Failed to install Vagrant"
    exit 1
  }
  msg_ok "Installed Vagrant"
}

# compare_virtualbox_version() {
#   local vb_version
#   local latest_version

#   vb_version=$(vboxmanage -v | cut -dr -f1)
#   latest_version=$(wget -qO- https://download.virtualbox.org/virtualbox/LATEST.TXT)

#   if [[ "$vb_version" != "$latest_version" ]]; then
#     msg_err "VirtualBox version $vb_version is not the latest version ($latest_version)"
#     return 1
#   fi
# }

main() {
  if ! command -v vboxmanage &> /dev/null; then
    install_dependencies
    add_virtualbox_repo
    install_virtualbox
    install_virtualbox_extensions_pack
    add_user_to_vbox_group
    msg_ok "VirtualBox has been installed. Please reboot your system."
  else
    msg_ok "VirtualBox is already installed"
  fi

  if ! command -v vagrant &> /dev/null; then
    add_vagrant_repo
    install_vagrant
    msg_ok "Vagrant has been installed"
  else
    msg_ok "Vagrant is already installed"
  fi
}

main
