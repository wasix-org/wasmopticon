#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export PORT="${PORT:-18383}"
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
greeting='MCP server is running. Connect your MCP client to /mcp.'
started=$SECONDS
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null &&
     [[ $(cat "$body") == "$greeting" ]]; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'mcp-edgejs failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done
echo "PASS greeting and readiness ($((SECONDS - started))s)"


rpc() {
  local result
  result=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -w '%{http_code} %{content_type}' \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H 'MCP-Protocol-Version: 2025-03-26' --data "$1" "$origin/mcp")
  [[ $result == '200 application/json'* ]]
}

rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"wasmopticon","version":"1"}}}'
jq -e '.id == 1 and .result.protocolVersion == "2025-03-26" and .result.serverInfo.name == "stackmachine-mcp-example" and (.result.capabilities.tools | type == "object")' "$body" >/dev/null
echo 'PASS MCP initialize handshake'

rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
jq -e '.id == 2 and [.result.tools[].name] == ["greet"]' "$body" >/dev/null
rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"greet","arguments":{"name":"wasmopticon"}}}'
jq -e '.id == 3 and .result.content == [{type:"text",text:"Hello, wasmopticon!"}]' "$body" >/dev/null
echo 'PASS MCP tools list and call'

headers="$run_dir/headers"
result=$(curl --noproxy '*' -sS --max-time 5 -D "$headers" -o "$body" -w '%{http_code}' "$origin/mcp")
[[ $result == 405 && $(cat "$body") == 'Method Not Allowed' ]]
tr -d '\r' <"$headers" | grep -ixq 'allow: POST'
result=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -w '%{http_code}' "$origin/missing")
[[ $result == 404 ]]
grep -Fq 'Cannot GET /missing' "$body"
echo 'PASS MCP method restriction and unmatched route'
