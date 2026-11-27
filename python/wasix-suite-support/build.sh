#!/usr/bin/env bash
set -euo pipefail

anybuild=$(realpath "$(command -v "${ANYBUILD_BIN:-anybuild}")")
wasmer=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
if [[ $("$anybuild" --version) != 0.33.3 ]]; then
    echo "This fixture requires Anybuild 0.33.3." >&2
    exit 1
fi

if [[ "$(uvx --version)" != "uvx 0.13.9 "* ]]; then
    echo "This fixture requires uvx 0.13.9 on PATH." >&2
    exit 1
fi

support=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
"$support/fetch-registry.sh"

cd -- "$1"
"$anybuild" build . --wasmer --wasmer-bin "$wasmer" --skip-prepare
manifest=.anybuild/wasmer/wasmer.toml
grep -Eq '^"python/python" = "=3\.13\.20"$' "$manifest" || {
    echo "Expected Anybuild to select python/python@=3.13.20." >&2
    exit 1
}

mkdir -p .anybuild/suite
build_tmp=$(mktemp -d .anybuild/suite/package.XXXXXX)
trap 'rm -rf -- "$build_tmp"' EXIT
if [[ ${2:-} = --reproducible ]]; then
    # WebC records volume paths and staged modification times.
    package_root=.anybuild/local/build
    package_manifest=$package_root/wasmer.toml
    sed -E 's|^(".*" = ").*/\.anybuild/local/build/|\1|' "$manifest" > "$package_manifest"
    find "$package_root" -exec touch -h -d "@946684800" -- {} +
    manifest=$package_manifest
fi
"$wasmer" package build "$manifest" --out "$build_tmp/package.webc"
mv -f -- "$build_tmp/package.webc" .anybuild/suite/package.webc
sha256sum .anybuild/suite/package.webc
