#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
wasmer=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
inputs="$project/.anybuild/inputs"
mkdir -p "$inputs/bin"

module_checksums() {
    printf '%s  %s\n' \
        28ea014e13af5711c1a324bf9faee45b4cf5e6e0e6e1cf0f84dad31c9aadd936 "$1/ffmpeg" \
        b8a82a01b85dbb815e19ed73e51e55fe33166515cc4f4e13462d648ebb5666b0 "$1/ffprobe"
}

if ! module_checksums "$inputs/bin" | sha256sum --check --status; then
    build_tmp=$(mktemp -d "$inputs/ffmpeg.XXXXXX")
    trap 'rm -rf -- "$build_tmp"' EXIT
    "$wasmer" package download 'wasmer/ffmpeg@=1.0.5' --out-path "$build_tmp/ffmpeg.webc"
    sha256sum --check <<< "d659dd3792bda6fd0377819ccb753908c160f2ead3a586452bcb3030ec4ff75d  $build_tmp/ffmpeg.webc"
    "$wasmer" package unpack "$build_tmp/ffmpeg.webc" --out-dir "$build_tmp/unpacked"
    module_checksums "$build_tmp/unpacked/modules" | sha256sum --check
    chmod +x "$build_tmp/unpacked/modules/"{ffmpeg,ffprobe}
    mv -f -- "$build_tmp/unpacked/modules/"{ffmpeg,ffprobe} "$inputs/bin/"
    rm -rf -- "$build_tmp"
    trap - EXIT
fi

exec "$project/../wasix-suite-support/build.sh" "$project" --reproducible
