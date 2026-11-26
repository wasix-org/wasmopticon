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
# Public server-action key for the local fixture build.
"$ANYBUILD_BIN" build . --wasmer --wasmer-bin "$WASMER_BIN" \
  --install-command 'npm ci --no-audit' \
  --build-command 'node seed-preview.mjs && npm exec --no -- next-bundle' \
  --env NEXT_SERVER_ACTIONS_ENCRYPTION_KEY=d2FzbW9wdGljb24tbG9jYWwtdGVzdC1rZXktb25seSE= \
  --env NEXT_TELEMETRY_DISABLED=1 --env VERCEL_TELEMETRY_DISABLED=1

mkdir -p .anybuild/suite
build_tmp=$(mktemp -d .anybuild/suite/package.XXXXXX)
trap 'if [[ -e "$build_tmp/package.webc" ]]; then unlink "$build_tmp/package.webc"; fi; rmdir "$build_tmp"' EXIT
# WebC records local volume paths and staged modification times.
package_root=.anybuild/local/build
# The build trace contains wall-clock timings and is private to the build.
rm -f -- "$package_root/app/.next-bundle/static/_next/__private/trace"
package_manifest=$package_root/wasmer.toml
sed -E 's|^(".*" = ").*/\.anybuild/local/build/|\1|' .anybuild/wasmer/wasmer.toml > "$package_manifest"
find "$package_root" -exec touch -h -d "@946684800" -- {} +
"$WASMER_BIN" package build "$package_manifest" --out "$build_tmp/package.webc"
mv -f -- "$build_tmp/package.webc" .anybuild/suite/package.webc
sha256sum "$package_manifest" .anybuild/suite/package.webc
