#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${WASMER_BIN:=wasmer}"
: "${REGISTRY_DIR:?Set REGISTRY_DIR to the local WebC registry root}"

registry="$PWD/registry.sha256"
(cd "$REGISTRY_DIR" && sha256sum --strict --quiet -c "$registry")
mkdir -p .anybuild/suite
run_dir=$(mktemp -d "$PWD/.anybuild/suite/functional.${WASIX_LANE:-unknown}.XXXXXX")
export WASMER_DIR="$run_dir/state"
export WASMER_CACHE_DIR="${WASMER_CACHE_DIR:-$run_dir/cache}"
echo "Functional evidence: $run_dir"

status=0
timeout -k 5 "${RUN_TIMEOUT:-90}" "$WASMER_BIN" run --cranelift --offline \
  --include-webc "$REGISTRY_DIR" --entrypoint start .anybuild/suite/package.webc \
  >"$run_dir/stdout" 2>"$run_dir/stderr" || status=$?
if (( status != 0 )); then
  echo "Worker command exited $status." >&2
  cat "$run_dir/stdout" "$run_dir/stderr" >&2
  exit "$status"
fi

if ! jq -es '. == [{primes: 9592, sum: 454396537, isolated: true, exitCode: 0}]' \
  "$run_dir/stdout" >/dev/null; then
  cat "$run_dir/stdout" "$run_dir/stderr" >&2
  exit 1
fi
echo 'PASS Worker computed the prime count and sum in isolation and exited cleanly'
