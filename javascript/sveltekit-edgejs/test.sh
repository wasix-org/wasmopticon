#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export PORT="${PORT:-18382}"
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
marker='<title>Sverdle</title>'
started=$SECONDS
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/sverdle" -o "$body" 2>/dev/null &&
     grep -Fq "$marker" "$body"; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'SvelteKit failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done
echo "PASS SvelteKit SSR readiness ($((SECONDS - started))s)"


grep -Fq 'action="?/enter"' "$body"
grep -Fq 'name="guess"' "$body"
echo 'PASS rendered Sverdle form and word grid'

headers="$run_dir/headers"
cookies="$run_dir/cookies"
result=$(curl --noproxy '*' -fsS --max-time 5 -o "$body" -D "$headers" -c "$cookies" -w '%{content_type}' \
  -H 'Accept: text/html' -H "Origin: $origin" --data-urlencode 'key=q' "$origin/sverdle?/update")
[[ $result == text/html* ]]
tr -d '\r' <"$headers" | grep -iq '^set-cookie: sverdle='
grep -Eq '<input name="guess"[^>]*value="q"' "$body"

curl --noproxy '*' -fsS --max-time 5 -o "$body" -b "$cookies" "$origin/sverdle"
grep -Eq '<input name="guess"[^>]*value="q"' "$body"
echo 'PASS Sverdle form action and cookie-backed SSR'

result=$(curl --noproxy '*' -fsS --max-time 5 -o "$body" -D "$headers" -b "$cookies" -c "$cookies" -w '%{content_type}' \
  -H 'Accept: application/json' -H "Origin: $origin" --data-urlencode 'key=w' "$origin/sverdle?/update")
[[ $result == application/json* ]]
jq -e '.type == "success" and .status == 204' "$body" >/dev/null
tr -d '\r' <"$headers" | grep -iq '^set-cookie: sverdle='
curl --noproxy '*' -fsS --max-time 5 -o "$body" -b "$cookies" "$origin/sverdle"
grep -Eq '<input name="guess"[^>]*value="w"' "$body"
echo 'PASS JSON action response and second persisted keypress'

result=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -w '%{http_code} %{content_type}' \
  -H 'Accept: text/html' "$origin/missing")
[[ $result == '404 text/html'* ]]
grep -Fq 'Not Found' "$body"
echo 'PASS missing route returns an HTML 404'
