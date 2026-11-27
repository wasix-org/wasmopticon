#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export PORT="${PORT:-18381}"
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
body="$run_dir/body"
marker='<h1>Astro Node Example</h1>'
started=$SECONDS
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null &&
     grep -Fq "$marker" "$body"; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'Astro failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done
echo "PASS Astro SSR readiness ($((SECONDS - started))s)"


for probe in first-request second-request; do
  result=$(curl --noproxy '*' -fsS --max-time 5 -o "$body" -w '%{content_type}' "$origin/?probe=$probe")
  [[ $result == text/html* ]]
  grep -Fq "<output id=\"request-probe\">$probe</output>" "$body"
  grep -Fq '<form action="/echo" method="post">' "$body"
done
echo 'PASS request-specific SSR and form markup'

headers="$run_dir/headers"
result=$(curl --noproxy '*' -fsS --max-time 5 -o "$body" -D "$headers" -w '%{content_type}' "$origin/echo")
[[ $result == application/json* ]]
jq -e '. == {message: "Rendered by Astro on Node."}' "$body" >/dev/null
tr -d '\r' <"$headers" | grep -iq '^x-fixture: astro-ssr$'

result=$(curl --noproxy '*' -fsS --max-time 5 -o "$body" -D "$headers" -w '%{content_type}' \
  -H "Origin: $origin" --data-urlencode 'message=Edge.js form probe' "$origin/echo")
[[ $result == application/json* ]]
jq -e '. == {message: "Edge.js form probe"}' "$body" >/dev/null
tr -d '\r' <"$headers" | grep -iq '^x-fixture: astro-ssr$'
echo 'PASS JSON route, form action and response header'

result=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -w '%{http_code}' "$origin/missing")
[[ $result == 404 ]]
echo 'PASS missing route returns HTTP 404'
