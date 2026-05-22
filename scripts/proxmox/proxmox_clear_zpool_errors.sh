#!/usr/bin/env bash

HEALTHCHECKS_URL=""

# Get the list of ZFS pool names
pool_list=$(zpool list -H -o name)

# Function to log messages with timestamps
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to send a signal to Healthchecks.io
signal_healthchecks() {
    local status=$1
    curl -m 10 --retry 5 "${HEALTHCHECKS_URL}/${status}" >/dev/null 2>&1
}

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    log "This script must be run as root."
    signal_healthchecks 1
    exit 1
fi

# Loop over each pool in the list
for pool_name in $pool_list; do

  # Get the status of the pool and grep for the "state:" line
  pool_status=$(zpool status $pool_name | grep "state:")

  # Check if the pool state is "DEGRADED"
  if echo "$pool_status" | grep -q "DEGRADED"; then

    # Run the "zpool clear" command on the affected pool
    if zpool clear $pool_name; then

        # Print a message to the console indicating that errors have been cleared
        log "Errors cleared for pool $pool_name"
        signal_healthchecks 0
    else
        log "Failed to clear errors for pool $pool_name"
        signal_healthchecks 1
    fi
  else
    log "No errors to clear for pool $pool_name"
    signal_healthchecks 0
  fi
done
