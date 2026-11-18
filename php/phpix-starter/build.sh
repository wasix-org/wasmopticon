#!/usr/bin/env bash
set -euo pipefail

anybuild_bin=$(command -v "${ANYBUILD_BIN:-anybuild}")
wasmer_bin=$(command -v "${WASMER_BIN:-wasmer}")
anybuild_bin=$(realpath -- "$anybuild_bin")
wasmer_bin=$(realpath -- "$wasmer_bin")
[[ $("$anybuild_bin" --version) == 0.33.3 ]] || {
    echo 'Anybuild 0.33.3 is required' >&2
    exit 1
}
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mkdir -p .anybuild/suite
./runtime-inputs.sh "$PWD/.anybuild/suite/registry"
"$anybuild_bin" build . --wasmer --wasmer-bin "$wasmer_bin"
manifest=.anybuild/wasmer/wasmer.toml
grep -Fx '"phpix/phpix-84-32bit" = "=0.3.1"' "$manifest"
build_tmp=$(mktemp -d .anybuild/suite/package.XXXXXX)
trap 'rm -rf -- "$build_tmp"' EXIT
# WebC records local volume paths and staged modification times.
package_root=.anybuild/local/build
package_manifest=$package_root/wasmer.toml
sed -E 's|^(".*" = ").*/\.anybuild/local/build/|\1|' "$manifest" > "$package_manifest"
find "$package_root" -exec touch -h -d "@946684800" -- {} +
"$wasmer_bin" package build "$package_manifest" --out "$build_tmp/package.webc"
mv -f -- "$build_tmp/package.webc" .anybuild/suite/package.webc
sha256sum .anybuild/suite/package.webc
