#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${ANYBUILD_BIN:=anybuild}"
: "${WASMER_BIN:=wasmer}"

if [[ $("$ANYBUILD_BIN" --version) != 0.33.3 ]]; then
  echo 'This fixture requires Anybuild 0.33.3.' >&2
  exit 1
fi
"$ANYBUILD_BIN" build . --wasmer --wasmer-bin "$WASMER_BIN" \
  --install-command 'npm ci --no-audit'

mkdir -p .anybuild/suite
build_tmp=$(mktemp -d .anybuild/suite/package.XXXXXX)
trap 'if [[ -e "$build_tmp/package.webc" ]]; then unlink "$build_tmp/package.webc"; fi; rmdir "$build_tmp"' EXIT
"$WASMER_BIN" package build .anybuild/wasmer/wasmer.toml --out "$build_tmp/package.webc"
mv -f -- "$build_tmp/package.webc" .anybuild/suite/package.webc
sha256sum .anybuild/wasmer/wasmer.toml .anybuild/suite/package.webc
