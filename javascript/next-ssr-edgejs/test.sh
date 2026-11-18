#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export PORT="${PORT:-18882}"
mkdir -p .anybuild/suite
run_dir=$(mktemp -d "$PWD/.anybuild/suite/functional.${WASIX_LANE:-unknown}.XXXXXX")
export WASMER_DIR="$run_dir/state"
export WASMER_CACHE_DIR="${WASMER_CACHE_DIR:-$run_dir/cache}"
echo "Functional evidence: $run_dir"

python3 - "$PORT" <<'PY'
import socket
import sys

with socket.socket() as listener:
    listener.bind(("127.0.0.1", int(sys.argv[1])))
PY

./serve.sh >"$run_dir/server.log" 2>&1 &
server_pid=$!
cleanup() {
  local status=$?
  trap - EXIT
  if kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    for ((attempt = 0; attempt < 30; attempt++)); do
      if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    kill -KILL "$server_pid" 2>/dev/null || true
  fi
  wait "$server_pid" 2>/dev/null || true
  if (( status != 0 )); then cat "$run_dir/server.log" >&2; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

origin="http://127.0.0.1:$PORT"
body="$run_dir/page.html"
started=$SECONDS
deadline=$((SECONDS + 120))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/?probe=edge-first" -o "$body" 2>/dev/null &&
     grep -Fq '<output id="qa-token">edge-first</output>' "$body"; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'Next.js failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done
echo "PASS request-time SSR and readiness ($((SECONDS - started))s)"

asset=$(python3 - "$body" <<'PY'
import re
import sys
from pathlib import Path

page = Path(sys.argv[1]).read_text()
match = re.search(r'src="(/_next/static/[^"]+\.js)"', page)
if not match:
    raise SystemExit("No emitted Next.js script in rendered HTML")
print(match[1])
PY
)
result=$(curl --noproxy '*' -fsS --max-time 5 -o "$run_dir/asset.js" -w '%{http_code} %{content_type}' "$origin$asset")
[[ "$result" == '200 application/javascript'* || "$result" == '200 text/javascript'* ]]
[[ -s "$run_dir/asset.js" ]]
echo "PASS emitted Next.js script: $asset"

curl --noproxy '*' -fsS --max-time 5 "$origin/?probe=edge-second" -o "$run_dir/second.html"
grep -Fq '<output id="qa-token">edge-second</output>' "$run_dir/second.html"
echo 'PASS second request renders a different query value'
