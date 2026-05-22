#!/usr/bin/env bash

# Colors for output
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NO_COLOR="\033[0m"

# Function to print messages in color
echo_with_color() {
  local color=$1
  shift
  echo -e "${color}$*${NO_COLOR}"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Function to check if firewalld is running
check_firewalld() {
  if ! systemctl is-active --quiet firewalld; then
    echo_with_color $RED "Error: firewalld is not running."
    exit 1
  fi
}

# Function to add a port to firewalld
add_port() {
  local port=$1
  local zone=$2
  sudo firewall-cmd --zone="$zone" --add-port="$port" --permanent
  if [ $? -eq 0 ]; then
    echo_with_color $GREEN "Successfully added port $port to zone $zone."
    sudo firewall-cmd --reload
  else
    echo_with_color $RED "Failed to add port $port to zone $zone."
  fi
}

# Function to remove a port from firewalld
remove_port() {
  local port=$1
  local zone=$2
  sudo firewall-cmd --zone="$zone" --remove-port="$port" --permanent
  if [ $? -eq 0 ]; then
    echo_with_color $GREEN "Successfully removed port $port from zone $zone."
    sudo firewall-cmd --reload
  else
    echo_with_color $RED "Failed to remove port $port from zone $zone."
  fi
}

# Function to list open ports in a zone
list_ports() {
  local zone=$1
  echo_with_color $GREEN "Open ports in zone $zone:"
  sudo firewall-cmd --zone="$zone" --list-ports
  if [ $? -ne 0 ]; then
    echo_with_color $RED "Failed to list ports for zone $zone."
  fi
}

# Function to restart firewalld
restart_firewalld() {
  sudo systemctl restart firewalld
  if [ $? -eq 0 ]; then
    echo_with_color $GREEN "Firewalld restarted."
  else
    echo_with_color $RED "Failed to restart firewalld."
  fi
}

# Check if firewalld is installed
if ! command_exists firewall-cmd; then
  echo_with_color $RED "Error: firewalld is not installed."
  exit 1
fi

# Check if firewalld is running
check_firewalld

# Ensure correct number of arguments
if [ "$#" -lt 2 ]; then
  echo_with_color $YELLOW "Usage: $0 {add|remove|list} <port/protocol> <zone>"
  exit 1
fi

# Parse arguments
action=$1
port=$2
zone=$3

# Execute appropriate action
case $action in
  add)
    if [ -z "$zone" ]; then
      echo_with_color $YELLOW "Usage: $0 add <port/protocol> <zone>"
      exit 1
    fi
    add_port "$port" "$zone"
    # restart_firewalld
    ;;
  remove)
    if [ -z "$zone" ]; then
      echo_with_color $YELLOW "Usage: $0 remove <port/protocol> <zone>"
      exit 1
    fi
    remove_port "$port" "$zone"
    # restart_firewalld
    ;;
  list)
    list_ports "$port"
    ;;
  *)
    echo_with_color $YELLOW "Usage: $0 {add|remove|list} <port/protocol> <zone>"
    exit 1
    ;;
esac

