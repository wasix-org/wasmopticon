#!/usr/bin/env bash
set -euo pipefail

anybuild=$(realpath "$(command -v "${ANYBUILD_BIN:-anybuild}")")
wasmer=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
python=$(realpath "$(command -v "${PYTHON_BIN:-python3.12}")")
[[ $("$anybuild" --version) == "0.33.3" ]] || { echo "Anybuild 0.33.3 is required." >&2; exit 1; }
[[ $(uv --version) == "uv 0.13.9 "* ]] || { echo "uv 0.13.9 is required." >&2; exit 1; }
[[ $("$python" -c 'import sys; print(sys.version_info[:2])') == "(3, 12)" ]] || {
    echo "CPython 3.12 is required." >&2
    exit 1
}

local_webc=${STATIC_WEB_SERVER_WEBC:-}
if [[ -n "$local_webc" ]]; then
    local_webc=$(realpath "$local_webc")
fi
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
umask 022

mkdir -p .suite .anybuild/suite
exec 9>.suite/build.lock
flock 9
build_tmp=$(mktemp -d .suite/build.XXXXXX)
trap 'rm -rf -- "$build_tmp"' EXIT
export UV_CACHE_DIR=${UV_CACHE_DIR:-"$PWD/.suite/uv-cache"}
export SOURCE_DATE_EPOCH=946684800

check_sha() {
    printf '%s  %s\n' "$1" "$2" | sha256sum --check
}

starter_rev=975b9a87074cdee9fc8d96d4f7afe6834f929aed
starter_sha=71610da685e535a91afa2607fff92e1f6b1618edafea8708830f5030c7e967dd
archive=".suite/mkdocs-starter-$starter_rev.tar.gz"
if [[ ! -f "$archive" ]]; then
    curl -qfsSL --retry 2 --max-time 60 \
        "https://codeload.github.com/wasmer-examples/mkdocs-wasmer-starter/tar.gz/$starter_rev" \
        -o "$build_tmp/starter.tar.gz"
    check_sha "$starter_sha" "$build_tmp/starter.tar.gz"
    mv -f -- "$build_tmp/starter.tar.gz" "$archive"
fi
check_sha "$starter_sha" "$archive"
mkdir "$build_tmp/source"
tar -xf "$archive" -C "$build_tmp/source" --strip-components=1

uv venv --python "$python" "$build_tmp/.venv"
uv pip sync --python "$build_tmp/.venv/bin/python" --require-hashes --only-binary :all: requirements.lock
"$build_tmp/.venv/bin/python" -m mkdocs build --strict \
    --config-file "$build_tmp/source/mkdocs.yml" --site-dir "$PWD/$build_tmp/site"

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
package_root=.anybuild/local/build
package_manifest=$package_root/wasmer.toml
sed -E 's#^(".*" = "|source = ").*/\.anybuild/local/build/#\1#' .anybuild/wasmer/wasmer.toml > "$package_manifest"
find "$package_root" -exec touch -h -d "@$SOURCE_DATE_EPOCH" -- {} +
package_tmp=$(mktemp -d .anybuild/suite/package.XXXXXX)
trap 'rm -rf -- "$build_tmp" "$package_tmp"' EXIT
"$wasmer" package build "$package_manifest" --out "$package_tmp/package.webc"
mv -f -- "$package_tmp/package.webc" .anybuild/suite/package.webc
sha256sum .anybuild/suite/package.webc
