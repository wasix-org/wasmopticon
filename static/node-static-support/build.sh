#!/usr/bin/env bash
set -euo pipefail

cd -- "$1"
source ./inputs.env
wasmer=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
anybuild=$(realpath "$(command -v "${ANYBUILD_BIN:-anybuild}")")
[[ $(node --version) == v26.13.1 && $(npm --version) == 11.20.0 && $("$anybuild" --version) == 0.33.3 ]]
umask 022
mkdir -p .suite .anybuild/suite
exec 9>.suite/build.lock
flock 9
work=$(mktemp -d .suite/build.XXXXXX)
trap 'rm -rf -- "$work"' EXIT

fetch() {
    local filename=$1 digest=$2 url=$3
    if [[ ! -f .suite/$filename ]]; then
        curl -fsSL --retry 2 --max-time 180 "$url" -o "$work/$filename"
        sha256sum --check <<<"$digest  $work/$filename"
        mv -- "$work/$filename" ".suite/$filename"
    fi
    sha256sum --check <<<"$digest  .suite/$filename"
}
fetch "$REV.tar.gz" "$SOURCE_SHA" "https://codeload.github.com/$REPO/tar.gz/$REV"
sws_sha=1e84109da307837d8160d23a77c36403ab44f7ec0c592b1cfe4a5bd79c968e08
if [[ -n ${STATIC_WEB_SERVER_WEBC:-} && ! -f .suite/sws.webc ]]; then
    cp -- "$STATIC_WEB_SERVER_WEBC" .suite/sws.webc
fi
fetch sws.webc "$sws_sha" "https://cdn.wasmer.io/webcimages/$sws_sha.webc"
"$wasmer" package unpack .suite/sws.webc --out-dir "$work/sws"
mv -f -- "$work/sws/modules/webserver" .suite/webserver.wasm

rm -rf -- .suite/source
mkdir .suite/source
archive_root="${REPO##*/}-$REV"
if [[ -n $ROOT ]]; then
    tar xf ".suite/$REV.tar.gz" -C .suite/source --strip-components=2 "$archive_root/$ROOT"
else
    tar xf ".suite/$REV.tar.gz" -C .suite/source --strip-components=1
fi
case ${BUILD_PROFILE:-} in
    next)
        # Keep Next's build manifest paths stable across clean exports.
        sed -i "/^const nextConfig: NextConfig = {/a\\  generateBuildId: async () => \"wasix-${REV:0:12}\"," \
            .suite/source/next.config.ts
        ;;
    nuxt)
        # This static fixture has no live deployment to poll for new manifests.
        sed -i "/^export default defineNuxtConfig({/a\\  buildId: \"wasix-${REV:0:12}\",\\n  experimental: { appManifest: false }," \
            .suite/source/nuxt.config.ts
        ;;
esac
cp -- "$(dirname -- "${BASH_SOURCE[0]}")/$CONFIG.toml" .suite/sws.toml
export SUITE_SOURCE="$PWD/.suite/source" SUITE_OUTPUT="$OUTPUT"
export SUITE_NUXT_NORMALIZE="$(realpath "$(dirname -- "${BASH_SOURCE[0]}")/normalize-nuxt.py")"
export NEXT_TELEMETRY_DISABLED=1 NUXT_TELEMETRY_DISABLED=1 GATSBY_TELEMETRY_DISABLED=1
export DO_NOT_TRACK=1 CI=1 GATSBY_CPU_COUNT=2 RAYON_NUM_THREADS=2
export npm_config_cache="${npm_config_cache:-$PWD/.suite/npm-cache}"
"$anybuild" build . --wasmer --wasmer-bin "$wasmer"

package_root=.anybuild/local/build
package_manifest=$package_root/wasmer.toml
sed -E 's#^(".*" = "|source = ").*/\.anybuild/local/build/#\1#' \
    .anybuild/wasmer/wasmer.toml >"$package_manifest"
find "$package_root" -exec touch -h -d '@946684800' -- {} +
"$wasmer" package build "$package_manifest" --out "$work/package.webc"
mv -f -- "$work/package.webc" .anybuild/suite/package.webc
sha256sum .anybuild/suite/package.webc
