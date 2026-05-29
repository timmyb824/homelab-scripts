#!/usr/bin/env bash
set -euo pipefail

# Image IDs referenced by ANY container (running or stopped)
mapfile -t referenced < <(
    podman ps -a --format '{{.ImageID}}' | sed '/^$/d' | sort -u
)

# All local image IDs
mapfile -t images < <(
    podman images --format '{{.ID}}' | sed '/^$/d' | sort -u
)

# Candidate images are those not referenced by any container
mapfile -t candidates < <(
    comm -23 <(printf "%s\n" "${images[@]}") <(printf "%s\n" "${referenced[@]}")
)

if ((${#candidates[@]} == 0)); then
    echo "No images are unreferenced by containers."
    exit 0
fi

#echo "Images not referenced by ANY container:"
#podman images --format '{{.ID}} {{.Repository}}:{{.Tag}}' \
#| awk 'NR==FNR{a[$1]=1;next} a[$1]{print}' <(printf "%s\n" "${candidates[@]}") -

#echo
#echo "To delete them, run:"
#printf 'podman rmi %s\n' "${candidates[*]}"

for id in "${candidates[@]}"; do
    podman images --format '{{.ID}} {{.Repository}}:{{.Tag}} {{.Size}}' | awk -v id="$id" '$1==id'
    read -r -p "Delete this image? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        podman rmi "$id"
    fi
done
