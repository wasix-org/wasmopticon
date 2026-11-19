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

check_sha() {
    printf '%s  %s\n' "$1" "$2" | sha256sum --check
}

fetch_archive() {
    local url=$1 checksum=$2 filename=$3
    if [[ ! -f ".suite/$filename" ]]; then
        curl -q --fail --silent --show-error --location --retry 2 --max-time 120 \
            "$url" -o "$build_tmp/$filename"
        check_sha "$checksum" "$build_tmp/$filename"
        mv -- "$build_tmp/$filename" ".suite/$filename"
    else
        check_sha "$checksum" ".suite/$filename"
    fi
}

template_rev=ccd67d29d46bdc38cfe6cd0275469fa8af17adc5
template_archive="static-website-$template_rev.tar.gz"
fetch_archive "https://codeload.github.com/wasmer-examples/static-website/tar.gz/$template_rev" \
    5cd1546d314e8518782ccff7be878e4e198e368a6aa7440b1bbcc41e4ff59257 "$template_archive"

mkdir "$build_tmp/template"
tar -xf ".suite/$template_archive" -C "$build_tmp/template" --strip-components=1
# Anybuild supplies the guest document root. test.sh supplies the bind address and port.
sed -E '/^(host|port|root)[[:space:]]*=/d' "$build_tmp/template/settings/config.toml" \
    >"$build_tmp/sws.toml"
mv -f -- "$build_tmp/sws.toml" .suite/sws.toml

sws_package=wasmer/static-web-server@=1.1.0
sws_sha=605963e04ea47c72d8f67e0a7ad45194c86fff97dacbf658f7883232730bca88
cached=.suite/registry/wasmer/static-web-server/1.1.0.webc
mkdir -p -- "$(dirname -- "$cached")"
if [[ -n "$local_webc" ]]; then
    cp -- "$local_webc" "$build_tmp/upstream.webc"
elif [[ -f "$cached" ]]; then
    cp -- "$cached" "$build_tmp/upstream.webc"
else
    "$wasmer" package download "$sws_package" --out-path "$build_tmp/upstream.webc"
fi
check_sha "$sws_sha" "$build_tmp/upstream.webc"
mv -f -- "$build_tmp/upstream.webc" "$cached"

"$anybuild" build . --wasmer --wasmer-bin "$wasmer" \
    --config "{\"static_dir\":\"$build_tmp/template/public\"}"
mkdir -p .anybuild/suite
"$wasmer" package build .anybuild/wasmer/wasmer.toml --out "$build_tmp/package.webc"
mv -f -- "$build_tmp/package.webc" .anybuild/suite/package.webc
