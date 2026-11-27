#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${WASMER_BIN:=wasmer}"
: "${WASIX_LANE:?Set WASIX_LANE to v1 or v2}"
: "${PORT:=18141}"
: "${DB_PORT:=18161}"

case "$WASIX_LANE" in
    v1) db_host=127.0.0.1; host=127.0.0.1; network=(--net) ;;
    v2) db_host=10.0.2.2; host=0.0.0.0; network=(--net --publish "127.0.0.1:$PORT:$PORT") ;;
    *) echo "Unknown WASIX_LANE: $WASIX_LANE" >&2; exit 2 ;;
esac

support=$(realpath ../wasix-suite-support)
registry=$(realpath "${REGISTRY_DIR:-"$support/.anybuild/registry"}")
while IFS=$'\t' read -r path sha; do
    sha256sum --check --status <<< "$sha  $registry/$path" || {
        echo "Missing or invalid registry input: $registry/$path. Run build.sh." >&2
        exit 1
    }
done < "$support/registry.tsv"
package=.anybuild/suite/package.webc
[[ -f "$package" ]] || { echo "Run build.sh first." >&2; exit 1; }

python3 - "$PORT" "$DB_PORT" <<'PY'
import socket
import sys

ports = [int(port) for port in sys.argv[1:]]
if any(not 1 <= port <= 65535 for port in ports) or ports[0] == ports[1]:
    sys.exit("PORT and DB_PORT must be distinct ports in 1..65535")
with socket.socket() as app, socket.socket() as database:
    app.bind(("127.0.0.1", ports[0]))
    database.bind(("127.0.0.1", ports[1]))
PY

redis_image=docker.io/library/redis@sha256:7f7d30b7fdd09467bac58198a1f166dd69789d348d4fe859cccb20e0cf287fbe
run_dir=$(mktemp -d "$PWD/.anybuild/suite/test.XXXXXX")
container="wasmopticon-fastapi-redis-${run_dir##*.}"
export WASMER_DIR="${WASMER_DIR:-$run_dir/state}"
export WASMER_CACHE_DIR="${WASMER_CACHE_DIR:-$run_dir/cache}"
server=
cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$server" ]] && kill -TERM "$server" 2>/dev/null; then
        for _ in {1..30}; do
            kill -0 "$server" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL "$server" 2>/dev/null || true
    fi
    if [[ -n "$server" ]]; then wait "$server" 2>/dev/null || true; fi
    if (( status != 0 )); then
        timeout -k 2 5 sudo -n docker logs "$container" >>"$run_dir/redis.log" 2>&1 || true
        for log in "$run_dir/redis.log" "$run_dir/server.log"; do
            if [[ -f "$log" ]]; then cat "$log" >&2; fi
        done
    fi
    timeout -k 2 10 sudo -n docker rm -fv "$container" >/dev/null 2>&1 || true
    printf 'Functional evidence: %s\n' "$run_dir"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

timeout -k 2 20 sudo -n docker run --rm --pull=never -d --name "$container" \
    -p "127.0.0.1:$DB_PORT:6379" "$redis_image" \
    redis-server --save "" --appendonly no --protected-mode no >"$run_dir/redis.log" 2>&1
redis_cli() {
    timeout -k 1 4 sudo -n docker exec "$container" redis-cli --raw "$@"
}
deadline=$((SECONDS + 20))
until [[ $(redis_cli PING 2>/dev/null) == PONG ]]; do
    if (( SECONDS >= deadline )); then echo "Redis did not become ready." >&2; exit 1; fi
    sleep 0.25
done

"$WASMER_BIN" run --cranelift --offline --include-webc "$registry" "${network[@]}" \
    --env "HOST=$host" --env "PORT=$PORT" --env "DB_HOST=$db_host" --env "DB_PORT=$DB_PORT" \
    --env PYTHONDONTWRITEBYTECODE=1 --env PYTHONPATH=/app:/opt/venv/lib/python3.13/site-packages \
    "$package" >"$run_dir/server.log" 2>&1 &
server=$!

origin="http://127.0.0.1:$PORT"
ready_timeout=${READY_TIMEOUT:-90}
[[ "$ready_timeout" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid READY_TIMEOUT." >&2; exit 1; }
deadline=$((SECONDS + ready_timeout))
until curl -q --noproxy '*' --max-time 1 -fsS -o /dev/null "$origin/"; do
    if ! kill -0 "$server" 2>/dev/null || (( SECONDS >= deadline )); then
        echo "FastAPI Redis fixture did not become ready." >&2
        exit 1
    fi
    sleep 0.25
done 2>"$run_dir/readiness.log"

deadline=$((SECONDS + 10))
until redis_cli INFO clients | tr -d '\r' | grep -Fxq 'blocked_clients:1'; do
    if (( SECONDS >= deadline )); then echo "Redis worker did not block on BLPOP." >&2; exit 1; fi
    sleep 0.1
done
echo "Verified Redis worker was blocked before jobs were enqueued"
timeout -k 2 30 python3 check.py "$origin"
