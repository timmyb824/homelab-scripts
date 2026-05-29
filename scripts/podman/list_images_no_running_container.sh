#!/usr/bin/env bash
set -euo pipefail

used_ids="$(
    podman ps --format '{{.ImageID}}' | sed '/^$/d' | sort -u
)"

podman images --format '{{.ID}} {{.Repository}}:{{.Tag}}' |
    while read -r id name; do
        if ! grep -qx "$id" <<<"$used_ids"; then
            printf "%s\t%s\n" "$id" "$name"
        fi
    done
