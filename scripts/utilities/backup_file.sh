#!/usr/bin/env bash
# Back up a config file before editing it. Refuses to proceed if the source doesn't exist,
# and exits non-zero if the copy fails, so callers can rely on set -e / checking $?.
#
# Usage: backup.sh <path-to-file>

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <path-to-file>" >&2
  exit 1
fi

SRC="$1"

if [ ! -f "$SRC" ]; then
  echo "ERROR: source file does not exist: $SRC" >&2
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${SRC}.bak.${TIMESTAMP}"

cp -p "$SRC" "$DEST"

if [ ! -f "$DEST" ]; then
  echo "ERROR: backup copy did not succeed: $DEST" >&2
  exit 1
fi

echo "Backed up $SRC -> $DEST"
