#!/usr/bin/env bash
set -euo pipefail

support=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
registry=${REGISTRY_DIR:-"$support/.anybuild/registry"}
tmp=
trap 'if [[ -n "$tmp" ]]; then rm -f -- "$tmp"; fi' EXIT

while IFS=$'\t' read -r path sha; do
    file=$registry/$path
    if ! sha256sum --check --status <<< "$sha  $file"; then
        mkdir -p -- "$(dirname -- "$file")"
        tmp=$(mktemp "$file.XXXXXX")
        curl -q -fLSs --retry 2 --max-time 120 "https://cdn.wasmer.io/webcimages/$sha.webc" -o "$tmp"
        sha256sum --check <<< "$sha  $tmp" >&2
        mv -f -- "$tmp" "$file"
        tmp=
    fi
    printf '%s' "$sha" > "$file.sha256"
done < "$support/registry.tsv"
