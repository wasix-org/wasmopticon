#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export PORT="${PORT:-18310}"
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
greeting='Hello from Fastify on Wasmer Edge'
started=$SECONDS
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null &&
     [[ $(cat "$body") == "$greeting" ]]; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'fastify-edgejs failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done
echo "PASS greeting and readiness ($((SECONDS - started))s)"


headers="$run_dir/headers"
json_request() {
  local path=$1 result
  shift
  result=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -D "$headers" \
    -w '%{http_code} %{content_type}' "$@" "$origin$path")
  [[ $result == "$expected_status application/json"* ]]
  tr -d '\r' <"$headers" | grep -ixq 'x-fixture: js-fastify'
  jq -e --argjson expected "$expected_body" '. == $expected' "$body" >/dev/null
}

expected_status=200
expected_body='{"framework":"fastify"}'
json_request /json
echo 'PASS JSON route, content type and response header'

expected_body='{"body":{"message":"paired Edge.js round trip","values":[1,true]},"probe":"from-client"}'
json_request /echo -H 'Content-Type: application/json' -H 'X-Probe: from-client' \
  --data '{"message":"paired Edge.js round trip","values":[1,true]}'
echo 'PASS POST JSON body and request header round trip'

expected_status=404
expected_body='{"error":"Not Found"}'
json_request /missing
echo 'PASS missing route returns HTTP 404 and JSON error'
