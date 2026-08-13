#!/usr/bin/env bash
set -euo pipefail

# Requires: VAULT_ADDR set, and either VAULT_TOKEN or an auth method configured
REDIS_PASSWORD=$(vault kv get -field=REDIS_PASSWORD secret/database)

exec /home/tbryant/.local/share/fnm/node-versions/v22.22.1/installation/bin/node \
  /home/tbryant/.local/share/fnm/node-versions/v22.22.1/installation/bin/redis-commander \
  --redis-host redis.homelab.lan \
  --redis-password "$REDIS_PASSWORD"
