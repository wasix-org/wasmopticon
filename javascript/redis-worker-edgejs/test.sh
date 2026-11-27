#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${WASMER_BIN:=wasmer}"
: "${REGISTRY_DIR:?Set REGISTRY_DIR to the local WebC registry root}"
: "${WASIX_LANE:?Set WASIX_LANE to v1 or v2}"
: "${PORT:=18394}"
: "${REDIS_PORT:=${DB_PORT:-18395}}"

image=docker.io/library/redis@sha256:7f7d30b7fdd09467bac58198a1f166dd69789d348d4fe859cccb20e0cf287fbe
registry="$PWD/registry.sha256"
(cd "$REGISTRY_DIR" && sha256sum --strict --quiet -c "$registry")
case "$WASIX_LANE" in
  v1) redis_host=127.0.0.1; network=(--net --env HOST=127.0.0.1 --env "PORT=$PORT") ;;
  v2) redis_host=10.0.2.2; network=(--net --publish "127.0.0.1:$PORT:8080" --env HOST=0.0.0.0 --env PORT=8080) ;;
  *) echo "Unknown WASIX_LANE: $WASIX_LANE" >&2; exit 2 ;;
esac

python3 - "$PORT" "$REDIS_PORT" <<'PYTHON'
import socket
import sys

with socket.socket() as app, socket.socket() as redis:
    for listener, value in zip((app, redis), sys.argv[1:]):
        port = int(value)
        if not 1 <= port <= 65535:
            sys.exit("Ports must be in 1..65535")
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", port))
        listener.listen()
PYTHON

mkdir -p .anybuild/suite
run_dir=$(mktemp -d "$PWD/.anybuild/suite/functional.${WASIX_LANE}.XXXXXX")
export WASMER_DIR="$run_dir/state"
export WASMER_CACHE_DIR="${WASMER_CACHE_DIR:-$run_dir/cache}"
echo "Functional evidence: $run_dir"
container="wasmopticon-js-redis-${run_dir##*.}"
server_pid=
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n $server_pid ]]; then
    kill "$server_pid" 2>/dev/null || true
    for ((attempt = 0; attempt < 30; attempt++)); do
      if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    kill -KILL "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if (( status != 0 )); then
    for log in docker.stdout guest.log body; do
      if [[ -f $run_dir/$log ]]; then cat "$run_dir/$log" >&2; fi
    done
  fi
  timeout -k 2 10 sudo docker rm -fv "$container" >/dev/null 2>&1 || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

timeout -k 2 20 sudo docker run --rm --pull=never -d --name "$container" \
  -p "127.0.0.1:$REDIS_PORT:6379" "$image" redis-server --save '' --appendonly no \
  >"$run_dir/docker.stdout"

redis() {
  timeout -k 1 4 sudo docker exec "$container" redis-cli --raw "$@"
}

deadline=$((SECONDS + 25))
until [[ $(redis PING 2>/dev/null) == PONG ]]; do
  if (( SECONDS >= deadline )); then echo 'Redis failed readiness' >&2; exit 1; fi
  sleep 0.25
done

"$WASMER_BIN" run --cranelift --offline "${network[@]}" --include-webc "$REGISTRY_DIR" \
  --env "REDIS_HOST=$redis_host" --env "REDIS_PORT=$REDIS_PORT" \
  --entrypoint start .anybuild/suite/package.webc >"$run_dir/guest.log" 2>&1 &
server_pid=$!

origin="http://127.0.0.1:$PORT"
body="$run_dir/body"
headers="$run_dir/headers"
deadline=$((SECONDS + 55))
while ! curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null ||
      ! jq -e '. == {queue:"wasmopticon-redis",worker:"ready"}' "$body" >/dev/null; do
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'BullMQ producer failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done

request() {
  local expected=$1 path=$2 actual
  shift 2
  actual=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -D "$headers" \
    -w '%{http_code} %{content_type}' "$@" "$origin$path")
  [[ $actual == "$expected application/json; charset=utf-8" ]] || return 1
  tr -d '\r' <"$headers" | grep -ixq 'cache-control: no-store'
}

request 202 /jobs -H 'Content-Type: application/json' --data '{"id":"odd","values":[1,3,5]}'
jq -e '. == {id:"odd"}' "$body" >/dev/null
request 202 /jobs -H 'Content-Type: application/json' --data '{"id":"even","values":[2,4,6,8]}'
jq -e '. == {id:"even"}' "$body" >/dev/null
echo 'PASS producer routes enqueue two jobs via HTTP'

completed() {
  local id=$1 sum=$2 deadline
  deadline=$((SECONDS + 20))
  while :; do
    request 200 "/jobs/$id"
    if jq -e --arg id "$id" --argjson sum "$sum" \
      '. == {id:$id,state:"completed",result:{id:$id,sum:$sum}}' "$body" >/dev/null; then
      return
    fi
    if (( SECONDS >= deadline )) || ! jq -e '.state == "pending"' "$body" >/dev/null; then
      echo "Job $id failed to complete with the expected result" >&2
      return 1
    fi
    sleep 0.2
  done
}
completed odd 9
completed even 20
echo 'PASS worker results are returned over HTTP'

prefix=bull:wasmopticon-redis
[[ $(redis ZCARD "$prefix:completed") == 2 ]]
[[ $(redis ZCARD "$prefix:failed") == 0 ]]
[[ $(redis LLEN "$prefix:wait") == 0 ]]
[[ $(redis LLEN "$prefix:active") == 0 ]]
redis HGET "$prefix:odd" returnvalue | jq -e '. == {id:"odd",sum:9}' >/dev/null
redis HGET "$prefix:even" returnvalue | jq -e '. == {id:"even",sum:20}' >/dev/null
request 404 /jobs/missing
jq -e '. == {error:"Job not found"}' "$body" >/dev/null
request 404 /missing
jq -e '. == {error:"Route not found"}' "$body" >/dev/null
echo 'PASS Redis stores both completed results, work queues are empty, and 404s return JSON'
