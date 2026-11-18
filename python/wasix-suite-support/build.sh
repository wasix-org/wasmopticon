#!/usr/bin/env bash
set -euo pipefail

anybuild=$(realpath "$(command -v "${ANYBUILD_BIN:-anybuild}")")
wasmer=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
if [[ $("$anybuild" --version) != 0.33.3 ]]; then
    echo "This fixture requires Anybuild 0.33.3." >&2
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
"$wasmer" package build "$manifest" --out "$build_tmp/package.webc"
mv -f -- "$build_tmp/package.webc" .anybuild/suite/package.webc
sha256sum .anybuild/suite/package.webc
