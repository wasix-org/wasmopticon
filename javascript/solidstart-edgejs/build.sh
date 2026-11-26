#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${ANYBUILD_BIN:=anybuild}"
: "${WASMER_BIN:=wasmer}"

if [[ $("$ANYBUILD_BIN" --version) != 0.33.3 ]]; then
  echo 'This fixture requires Anybuild 0.33.3.' >&2
  exit 1
fi
if [[ $(node --version) != v26.13.1 || $(npm --version) != 11.20.0 ]]; then
  echo 'Put Node 26.13.1 and npm 11.20.0 on PATH before building.' >&2
  exit 1
fi
"$ANYBUILD_BIN" build . --wasmer --wasmer-bin "$WASMER_BIN" \
  --install-command 'npm ci --no-audit' \
  --build-command 'npm run build && rm -rf .vinxi'

mkdir -p .anybuild/suite
build_tmp=$(mktemp -d .anybuild/suite/package.XXXXXX)
trap 'if [[ -e "$build_tmp/package.webc" ]]; then unlink "$build_tmp/package.webc"; fi; rmdir "$build_tmp"' EXIT
# WebC records local volume paths and staged modification times.
package_root=.anybuild/local/build
# Nitro records the wall-clock build time in its deployment metadata.
node --input-type=module - "$package_root/app/.output/nitro.json" \
  "$package_root/app/.output/server/chunks/nitro/nitro.mjs" <<'JS'
import { readFileSync, writeFileSync } from "node:fs";
const path = process.argv[2];
const metadata = JSON.parse(readFileSync(path, "utf8"));
metadata.date = "2000-01-01T00:00:00.000Z";
writeFileSync(path, JSON.stringify(metadata, null, 2) + "\n");

// Nitro's parallel asset collection records staging mtimes and insertion order.
const bundlePath = process.argv[3];
const bundle = readFileSync(bundlePath, "utf8");
const assetTable = /^const assets = (\{[\s\S]*?^\});$/m;
if (!assetTable.test(bundle)) throw new Error("Nitro public asset table not found");
const normalizedBundle = bundle.replace(assetTable, (_match, table) => {
  const assets = JSON.parse(table);
  const ordered = Object.fromEntries(Object.keys(assets).sort().map((url) => {
    const asset = assets[url];
    if (asset.mtime) asset.mtime = "2000-01-01T00:00:00.000Z";
    return [url, asset];
  }));
  return "const assets = " + JSON.stringify(ordered, null, 2) + ";";
});
writeFileSync(bundlePath, normalizedBundle);
JS
package_manifest=$package_root/wasmer.toml
sed -E 's|^(".*" = ").*/\.anybuild/local/build/|\1|' .anybuild/wasmer/wasmer.toml > "$package_manifest"
find "$package_root" -exec touch -h -d "@946684800" -- {} +
"$WASMER_BIN" package build "$package_manifest" --out "$build_tmp/package.webc"
mv -f -- "$build_tmp/package.webc" .anybuild/suite/package.webc
sha256sum "$package_manifest" .anybuild/suite/package.webc
