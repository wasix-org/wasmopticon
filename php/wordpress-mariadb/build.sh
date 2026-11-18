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
source ./inputs.env

suite=$PWD/.anybuild/suite
mkdir -p "$suite"
../phpix-starter/runtime-inputs.sh "$suite/registry"
build_tmp=$(mktemp -d "$suite/build.XXXXXX")
trap 'rm -rf -- "$build_tmp"' EXIT
archive=$suite/wordpress-$WP_VERSION.tar.gz
if [[ ! -f $archive ]] || ! sha256sum --check --status <<<"$WP_SHA256  $archive"; then
    curl --fail --silent --show-error --location --retry 3 --max-time 180 \
        "https://wordpress.org/wordpress-$WP_VERSION.tar.gz" -o "$build_tmp/wordpress.tar.gz"
    sha256sum --check <<<"$WP_SHA256  $build_tmp/wordpress.tar.gz"
    mv -f -- "$build_tmp/wordpress.tar.gz" "$archive"
fi
tar -xzf "$archive" -C "$build_tmp"
project=$build_tmp/wordpress
# Use a single test theme and no bundled plugins.
rm -rf -- "$project/wp-content/themes" "$project/wp-content/plugins"
cp -R -- site/. "$project/"
cp -- Anybuild "$project/"
(
    cd -- "$project"
    "$anybuild_bin" build . --wasmer --wasmer-bin "$wasmer_bin"
)
staged=$project/.anybuild
manifest=$staged/wasmer/wasmer.toml
sha256sum --check <<<"$WP_CLI_SHA256  $staged/local/build/opt/assets/wp-cli.phar"
grep -Fx '"phpix/phpix-84-32bit" = "=0.3.1"' "$manifest"
grep -Fx '"wasmer/bash" = "=1.0.25"' "$manifest"
# WebC records local volume paths and staged modification times.
package_root=$staged/local/build
package_manifest=$package_root/wasmer.toml
sed -E 's|^(".*" = ").*/\.anybuild/local/build/|\1|' "$manifest" > "$package_manifest"
find "$package_root" -exec touch -h -d "@946684800" -- {} +
"$wasmer_bin" package build "$package_manifest" --out "$build_tmp/package.webc"
# Keep generated files at their original absolute paths for inspection.
mv -f -- "$build_tmp/package.webc" "$suite/package.webc"
ln -s "${build_tmp##*/}/wordpress/.anybuild/wasmer" "$build_tmp/manifest"
mv -Tf -- "$build_tmp/manifest" "$suite/manifest"
trap - EXIT
sha256sum "$suite/package.webc"
