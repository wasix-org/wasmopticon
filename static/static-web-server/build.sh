#!/usr/bin/env bash
set -euo pipefail

anybuild=$(command -v "${ANYBUILD_BIN:-anybuild}") || { echo "Set ANYBUILD_BIN to Anybuild." >&2; exit 1; }
wasmer=$(command -v "${WASMER_BIN:-wasmer}") || { echo "Set WASMER_BIN to Wasmer." >&2; exit 1; }
anybuild=$(realpath "$anybuild")
wasmer=$(realpath "$wasmer")
local_webc=${STATIC_WEB_SERVER_WEBC:-}
if [[ -n "$local_webc" ]]; then
    local_webc=$(realpath "$local_webc")
fi
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
umask 022
mkdir -p .suite
exec 9>.suite/build.lock
flock 9
build_tmp=$(mktemp -d .suite/build.XXXXXX)
trap 'rm -rf -- "$build_tmp"' EXIT

package=wasmer/static-web-server@=2.44.0
sha256=1e84109da307837d8160d23a77c36403ab44f7ec0c592b1cfe4a5bd79c968e08
cached=.suite/static-web-server-2.44.0.webc
if [[ -n "$local_webc" ]]; then
    cp -- "$local_webc" "$build_tmp/upstream.webc"
elif [[ -f "$cached" ]]; then
    cp -- "$cached" "$build_tmp/upstream.webc"
else
    "$wasmer" package download "$package" --out-path "$build_tmp/upstream.webc"
fi
printf '%s  %s\n' "$sha256" "$build_tmp/upstream.webc" | sha256sum --check
mv -f -- "$build_tmp/upstream.webc" "$cached"

"$wasmer" package unpack "$cached" --out-dir "$build_tmp/upstream"
mv -f -- "$build_tmp/upstream/modules/webserver" .suite/webserver.wasm

"$anybuild" build . --wasmer --wasmer-bin "$wasmer"
"$wasmer" package build .anybuild/wasmer/wasmer.toml --out "$build_tmp/package.webc"
mv -f -- "$build_tmp/package.webc" .suite/package.webc
