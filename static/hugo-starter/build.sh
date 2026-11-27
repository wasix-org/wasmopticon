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

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)
        hugo_arch=amd64
        hugo_sha=90f3b4df86fde372d38d0bda7743f1a74d754b9eabecaf588fb5d9acbf9323e1
        ;;
    Linux-aarch64)
        hugo_arch=arm64
        hugo_sha=f0089c7f6ae8032cdc436b454c4651637ed9a8932f3dad9dd804fd2623a91930
        ;;
    *)
        echo "This fixture uses Hugo release archives for Linux amd64 or arm64." >&2
        exit 1
        ;;
esac

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

starter_rev=098cecbf023c3f0522f15381fe34241eb43fb1b3
starter_archive="hugo-starter-$starter_rev.tar.gz"
fetch_archive "https://codeload.github.com/wasmer-examples/hugo-wasmer-starter/tar.gz/$starter_rev" \
    c225c4c207f82e43d38272e8dcc28720e03dacf91dd9a7050fce01c7da3a2c99 "$starter_archive"
hugo_version=0.121.2
hugo_archive="hugo_extended_${hugo_version}_linux-$hugo_arch.tar.gz"
fetch_archive "https://github.com/gohugoio/hugo/releases/download/v$hugo_version/$hugo_archive" \
    "$hugo_sha" "$hugo_archive"

mkdir "$build_tmp/source"
tar -xf ".suite/$starter_archive" -C "$build_tmp/source" --strip-components=1
tar -xf ".suite/$hugo_archive" -C "$build_tmp" hugo
# The upstream sample post is marked as a draft. Include it for the preview.
"$build_tmp/hugo" --source "$build_tmp/source" --destination "$PWD/$build_tmp/site" \
    --minify --buildDrafts
# Keep the stylesheet's source map without its temporary build directory.
python3 - "$build_tmp/site/ananke/css/main.css.map" <<'PYTHON'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
source_map = json.loads(path.read_text())
source_map.pop("sourceRoot", None)
path.write_text(json.dumps(source_map, separators=(",", ":")) + "\n")
PYTHON

sws_package=wasmer/static-web-server@=2.44.0
sws_sha=1e84109da307837d8160d23a77c36403ab44f7ec0c592b1cfe4a5bd79c968e08
cached=.suite/static-web-server-2.44.0.webc
if [[ -n "$local_webc" ]]; then
    cp -- "$local_webc" "$build_tmp/upstream.webc"
elif [[ -f "$cached" ]]; then
    cp -- "$cached" "$build_tmp/upstream.webc"
else
    "$wasmer" package download "$sws_package" --out-path "$build_tmp/upstream.webc"
fi
check_sha "$sws_sha" "$build_tmp/upstream.webc"
mv -f -- "$build_tmp/upstream.webc" "$cached"

"$wasmer" package unpack "$cached" --out-dir "$build_tmp/upstream"
mv -f -- "$build_tmp/upstream/modules/webserver" .suite/webserver.wasm

"$anybuild" build . --wasmer --wasmer-bin "$wasmer" \
    --config "{\"static_dir\":\"$build_tmp/site\"}"
mkdir -p .anybuild/suite
# WebC records local volume paths and staged modification times.
package_root=.anybuild/local/build
package_manifest=$package_root/wasmer.toml
sed -E 's#^(".*" = "|source = ").*/\.anybuild/local/build/#\1#' .anybuild/wasmer/wasmer.toml > "$package_manifest"
find "$package_root" -exec touch -h -d "@946684800" -- {} +
"$wasmer" package build "$package_manifest" --out "$build_tmp/package.webc"
mv -f -- "$build_tmp/package.webc" .anybuild/suite/package.webc
sha256sum "$package_manifest" .anybuild/suite/package.webc
