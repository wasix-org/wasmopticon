#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
wasmer=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
inputs="$project/.anybuild/inputs"
mkdir -p "$inputs"

pandoc_sha=48d9ceed3ef805f6acc28e6f58c2439cdeb1f71864244fffcc155e2c045aa7fc
if ! sha256sum --check --status <<< "$pandoc_sha  $inputs/pandoc"; then
    build_tmp=$(mktemp -d "$inputs/pandoc.XXXXXX")
    trap 'rm -rf -- "$build_tmp"' EXIT
    "$wasmer" package download 'wasmer/pandoc@=0.0.1' --out-path "$build_tmp/pandoc.webc"
    sha256sum --check <<< "c7cd7834b11919cc0e8788f164acb4472dede42bf42f550509bd3da53d8cf60d  $build_tmp/pandoc.webc"
    "$wasmer" package unpack "$build_tmp/pandoc.webc" --out-dir "$build_tmp/unpacked"
    sha256sum --check <<< "$pandoc_sha  $build_tmp/unpacked/modules/pandoc"
    chmod +x "$build_tmp/unpacked/modules/pandoc"
    mv -f -- "$build_tmp/unpacked/modules/pandoc" "$inputs/pandoc"
    rm -rf -- "$build_tmp"
    trap - EXIT
fi

exec "$project/../wasix-suite-support/build.sh" "$project" --reproducible
