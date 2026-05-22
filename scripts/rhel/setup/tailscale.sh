#!/usr/bin/env bash

source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

install_tailscale() {
  if ! command_exists tailscale; then
    if curl -fsSL https://tailscale.com/install.sh | sh; then
      echo_with_color $GREEN_COLOR "Tailscale has been installed successfully!"
    else
      exit_with_error "Failed to install Tailscale!"
    fi
  else
    echo_with_color $YELLOW_COLOR "Tailscale is already installed!"
    return 1
  fi
}

login_tailscale() {
  read -sp "Enter your Tailscale login key: " TS_KEY
  echo
  if ! sudo tailscale up --authkey="$TS_KEY" --operator="$USER" --accept-routes=true; then
    exit_with_error "Failed to login Tailscale!"
  fi
  echo_with_color $GREEN_COLOR "Tailscale has been logged in successfully!"
}

set_autoupdate_if_supported() {
  if command_exists tailscale; then
    if tailscale set --auto-update=true; then
      echo_with_color $GREEN_COLOR "Tailscale auto-update has been enabled!"
    else
      echo_with_color $YELLOW_COLOR "Tailscale auto-update is not supported!"
    fi
  fi
}

install_tailscale
login_tailscale
set_autoupdate_if_supported


