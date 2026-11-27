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
fixture=$PWD
variant=${1:?Choose mainroad, ink, paper-mod, m10c, or photophobia}
read -r selected root repository rev theme_sha port < <(awk -v name="$variant" '$1 == name { print; exit }' themes.tsv) || {
    echo "Unknown theme: $variant" >&2
    exit 2
}
mkdir -p ".suite/$variant"
cd ".suite/$variant"
cp -- "$fixture/Anybuild" .
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

hugo_version=0.121.2
hugo_archive="hugo_extended_${hugo_version}_linux-$hugo_arch.tar.gz"
fetch_archive "https://github.com/gohugoio/hugo/releases/download/v$hugo_version/$hugo_archive" \
    "$hugo_sha" "$hugo_archive"
theme_archive="$variant-$rev.tar.gz"
fetch_archive "https://codeload.github.com/$repository/tar.gz/$rev" "$theme_sha" "$theme_archive"

source=$build_tmp/source
theme=$source/themes/fixture
mkdir -p "$theme"
cp -- "$fixture/hugo.toml" "$source/"
cp -R -- "$fixture/content" "$source/"
tar -xf ".suite/$theme_archive" -C "$theme" --strip-components=1
if [[ ! -s $theme/layouts/404.html ]]; then
    mkdir -p "$source/layouts"
    cp -- "$fixture/layouts/404.html" "$source/layouts/"
fi

case "$variant" in
    mainroad)
        mkdir -p "$source/static"
        cp -- "$theme/images/screenshot.png" "$source/static/theme-preview.png"
        sed -i '/^categories =/a thumbnail = "theme-preview.png"' "$source/content/posts/fixture.md"
        ;;
    paper-mod)
        printf '\n[outputs]\nhome = ["HTML", "RSS", "JSON"]\n' >>"$source/hugo.toml"
        ;;
    photophobia)
        mkdir -p "$source/assets" "$source/layouts/shortcodes"
        cp -- "$theme/images/screenshot.png" "$source/assets/fixture.png"
        cp -- "$fixture/layouts/shortcodes/fixture-image.html" "$source/layouts/shortcodes/"
        printf '\n{{< fixture-image >}}\n' >>"$source/content/posts/fixture.md"
        ;;
esac
tar -xf ".suite/$hugo_archive" -C "$build_tmp" hugo
HUGO_CACHEDIR="$PWD/$build_tmp/cache" "$build_tmp/hugo" --source "$source" \
    --destination "$PWD/$build_tmp/site" --minify

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
# Retain the export from this package for byte-exact HTTP comparisons.
rm -rf -- .suite/site
mv -- "$build_tmp/site" .suite/site
mv -f -- "$build_tmp/package.webc" .anybuild/suite/package.webc
sha256sum "$package_manifest" .anybuild/suite/package.webc
