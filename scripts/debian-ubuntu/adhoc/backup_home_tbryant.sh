#!/usr/bin/env bash
set -euo pipefail

LOG=/tmp/pihole2_home_backup.log
PING_URL="https://healthchecks.timmybtech.com/ping/$HOME_TBRYANT_BACKUP_HEALTHCHECK_ID"￼

rsync -a --delete /home/tbryant/ /mnt/bryantnas/pihole2_backups/home_tbryant/ >>"$LOG" 2>&1
status=$?

# Always ping, with exit status
curl -fsS -m 10 --retry 5 -o /dev/null "${PING_URL}/${status}" || true

exit "$status"
