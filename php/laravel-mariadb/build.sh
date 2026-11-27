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
fixture=$PWD
suite=$fixture/.anybuild/suite
mkdir -p "$suite"
archive=$suite/examples-$EXAMPLES_REV.tar.gz
build_tmp=$(mktemp -d "$suite/build.XXXXXX")
trap 'rm -rf -- "$build_tmp"' EXIT

if [[ ! -f $archive ]] || ! sha256sum --check --status <<<"$EXAMPLES_SHA256  $archive"; then
    if [[ -n ${EXAMPLES_ARCHIVE:-} ]]; then
        cp -- "$EXAMPLES_ARCHIVE" "$build_tmp/examples.tar.gz"
    else
        curl --fail --silent --show-error --location --retry 3 --max-time 120 \
            "https://codeload.github.com/wasmerio/examples/tar.gz/$EXAMPLES_REV" \
            -o "$build_tmp/examples.tar.gz"
    fi
    sha256sum --check <<<"$EXAMPLES_SHA256  $build_tmp/examples.tar.gz"
    mv -f -- "$build_tmp/examples.tar.gz" "$archive"
fi
tar -xzf "$archive" -C "$build_tmp" -- "examples-$EXAMPLES_REV/$TEMPLATE_ROOT"
project=$build_tmp/examples-$EXAMPLES_REV/$TEMPLATE_ROOT
cmp -- "$fixture/composer.lock" "$project/composer.lock"
cp -- "$fixture/Anybuild" "$project/Anybuild"
export COMPOSER_HOME=${COMPOSER_HOME:-$suite/composer}
export COMPOSER_CACHE_DIR=${COMPOSER_CACHE_DIR:-$COMPOSER_HOME/cache}
export COMPOSER_FUND=0

cp -R -- "$fixture/overlay/." "$project/"
printf "\nrequire __DIR__.'/suite.php';\n" >> "$project/routes/web.php"
../phpix-starter/runtime-inputs.sh "$suite/registry"
(
    cd -- "$project"
    composer install --no-dev --optimize-autoloader --no-interaction --no-scripts
    cmp -- "$fixture/composer.lock" composer.lock
    "$anybuild_bin" build . --wasmer --wasmer-bin "$wasmer_bin"
)
manifest=$project/.anybuild/wasmer/wasmer.toml
grep -Fx '"phpix/phpix-84-32bit" = "=0.3.1"' "$manifest"
# WebC records local volume paths and staged modification times.
package_root=$project/.anybuild/local/build
package_manifest=$package_root/wasmer.toml
sed -E 's|^(".*" = ").*/\.anybuild/local/build/|\1|' "$manifest" > "$package_manifest"
find "$package_root" -exec touch -h -d "@946684800" -- {} +
"$wasmer_bin" package build "$package_manifest" --out "$build_tmp/package.webc"
mv -f -- "$build_tmp/package.webc" .anybuild/suite/package.webc
sha256sum .anybuild/suite/package.webc
