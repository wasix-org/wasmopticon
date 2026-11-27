#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${WASMER_BIN:=wasmer}"
: "${REGISTRY_DIR:?Set REGISTRY_DIR to the local WebC registry root}"
: "${WASIX_LANE:?Set WASIX_LANE to v1 or v2}"
: "${PORT:=18389}"
: "${UPSTREAM_PORT:=0}"

registry_checksums="$PWD/registry.sha256"
(cd "$REGISTRY_DIR" && sha256sum --strict --quiet -c "$registry_checksums")
mkdir -p .anybuild/suite
run_dir=$(mktemp -d "$PWD/.anybuild/suite/functional.$WASIX_LANE.XXXXXX")
export WASMER_DIR="$run_dir/state"
export WASMER_CACHE_DIR="${WASMER_CACHE_DIR:-$run_dir/cache}"
echo "Functional evidence: $run_dir"

case "$WASIX_LANE" in
  v1)
    upstream_host=127.0.0.1
    network=(--net --env HOST=127.0.0.1 --env "PORT=$PORT")
    ;;
  v2)
    upstream_host=10.0.2.2
    network=(--net --publish "127.0.0.1:$PORT:8080" --env HOST=0.0.0.0 --env PORT=8080)
    ;;
  *) printf 'Unknown WASIX_LANE: %s\n' "$WASIX_LANE" >&2; exit 2 ;;
esac

python3 - "$PORT" <<'PY'
import socket
import sys

with socket.socket() as listener:
    listener.bind(("127.0.0.1", int(sys.argv[1])))
PY

: >"$run_dir/upstream.log"
python3 upstream.py "$UPSTREAM_PORT" >"$run_dir/upstream.log" 2>&1 &
upstream_pid=$!
server_pid=
cleanup() {
  local status=$?
  trap - EXIT
  for pid in "$server_pid" "$upstream_pid"; do
    [[ -n "$pid" ]] || continue
    if kill -TERM "$pid" 2>/dev/null; then
      for ((i=0; i<30; i++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
      done
      kill -KILL "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  done
  if (( status != 0 )); then
    cat "$run_dir/upstream.log" >&2
    if [[ -f "$run_dir/server.log" ]]; then cat "$run_dir/server.log" >&2; fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

deadline=$((SECONDS + 10))
upstream_port=
while :; do
  read -r upstream_port <"$run_dir/upstream.log" || true
  if [[ "$upstream_port" =~ ^[1-9][0-9]{0,4}$ ]]; then break; fi
  kill -0 "$upstream_pid" 2>/dev/null && (( SECONDS < deadline )) || exit 1
  sleep 0.1
done

"$WASMER_BIN" run --cranelift --offline --include-webc "$REGISTRY_DIR" \
  "${network[@]}" --env "UPSTREAM_ORIGIN=http://$upstream_host:$upstream_port" \
  --entrypoint start .anybuild/suite/package.webc >"$run_dir/server.log" 2>&1 &
server_pid=$!
origin="http://127.0.0.1:$PORT"
body="$run_dir/body"
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null &&
     jq -e '. == {fixture:"outbound-fetch"}' "$body" >/dev/null; then
    break
  fi
  kill -0 "$server_pid" 2>/dev/null && (( SECONDS < deadline )) || exit 1
  sleep 0.25
done

request() {
  local status=$1 route=$2 expected=$3 actual
  actual=$(curl --noproxy '*' -sS --max-time 6 -o "$body" \
    -w '%{http_code} %{content_type}' "$origin/$route")
  if [[ "$actual" != "$status application/json" ]] ||
     ! jq -e --argjson expected "$expected" '. == $expected' "$body" >/dev/null; then
    printf 'Unexpected %s response (%s)\n' "$route" "$actual" >&2
    cat "$body" >&2
    return 1
  fi
}

request 200 json '{"source":"host-upstream","probe":"from-guest"}'
echo 'PASS guest fetch returns upstream JSON and forwards the probe header'
request 404 missing '{"error":"missing at upstream"}'
echo 'PASS upstream HTTP 404 and JSON survive fetch'
request 504 timeout '{"error":"upstream timeout"}'
grep -Fxq 'GET /slow' "$run_dir/upstream.log"
echo 'PASS guest aborts a slow request that reached the upstream'
