#!/usr/bin/env bash
# Add an AdGuard Home DNS rewrite via the REST API.
# Exits 0 on success (including "already exists"), non-zero otherwise so the caller
# knows to fall back to the SSH + config-edit path (see references/adguard.md).
#
# Usage: adguard_rewrite.sh <fqdn> <adguard-user> <adguard-password> [answer]
#   answer defaults to traefik.local.timmybtech.com

set -uo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <fqdn> <adguard-user> <adguard-password> [answer]" >&2
  exit 1
fi

FQDN="$1"
ANSWER="${2:-traefik.local.timmybtech.com}"
USER=$(op read op://Personal/adguard-timmybtech/username)
PASS=$(op read op://Personal/adguard-timmybtech/password)
BASE_URL="https://adguard.local.timmybtech.com"

RESPONSE=$(curl -s -o /tmp/adguard_response.$$ -w "%{http_code}" \
  -u "${USER}:${PASS}" \
  -X POST "${BASE_URL}/control/rewrite/add" \
  -H "Content-Type: application/json" \
  -d "{\"domain\": \"${FQDN}\", \"answer\": \"${ANSWER}\"}")

BODY=$(cat /tmp/adguard_response.$$ 2>/dev/null || echo "")
rm -f /tmp/adguard_response.$$

case "$RESPONSE" in
  200|204)
    echo "OK: added rewrite ${FQDN} -> ${ANSWER}"
    exit 0
    ;;
  400)
    echo "NOTE: AdGuard returned 400 (often means rewrite already exists). Body: ${BODY}"
    echo "Verify with: curl -s -u \"${USER}:***\" ${BASE_URL}/control/rewrite/list | grep ${FQDN}"
    exit 2
    ;;
  401|403)
    echo "ERROR: auth failed (HTTP ${RESPONSE}). Do not retry with guessed credentials." >&2
    exit 3
    ;;
  *)
    echo "ERROR: unexpected HTTP ${RESPONSE}. Body: ${BODY}" >&2
    echo "Falling back to SSH + direct config edit (see references/adguard.md)." >&2
    exit 4
    ;;
esac
