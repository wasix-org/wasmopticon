#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
registry=${1:?usage: runtime-inputs.sh REGISTRY_DIR}
mkdir -p -- "$registry"
tmp=$(mktemp -d "$registry/.download.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
while read -r path digest; do
    [[ -n $path && $path != \#* ]] || continue
    target=$registry/$path
    if [[ ! -f $target ]] || ! sha256sum --check --status <<<"$digest  $target"; then
        mkdir -p -- "$(dirname -- "$target")"
        if [[ -n ${WEBC_SOURCE_DIR:-} && -f $WEBC_SOURCE_DIR/$path ]]; then
            cp -- "$WEBC_SOURCE_DIR/$path" "$tmp/package.webc"
        else
            curl --fail --silent --show-error --location --retry 3 --max-time 120 \
                "https://cdn.wasmer.io/webcimages/$digest.webc" -o "$tmp/package.webc"
        fi
        sha256sum --check <<<"$digest  $tmp/package.webc"
        mv -f -- "$tmp/package.webc" "$target"
    fi
    printf '%s\n' "$digest" > "$tmp/package.sha256"
    mv -f -- "$tmp/package.sha256" "${target%.webc}.sha256"
done < runtime.tsv
