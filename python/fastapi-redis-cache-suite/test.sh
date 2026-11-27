#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
cd -- "$project"
export PORT=${PORT:-18143} DB_PORT=${DB_PORT:-18163}
[[ "$DB_PORT" =~ ^[1-9][0-9]{0,4}$ ]] && (( DB_PORT <= 65535 )) || {
    echo "DB_PORT must be in 1..65535." >&2
    exit 2
}
export SUITE_WASMER_BIN
SUITE_WASMER_BIN=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
run_help=$("$SUITE_WASMER_BIN" run --help)
export SUITE_REDIS_HOST=127.0.0.1
if [[ "$run_help" == *'--publish <'* ]]; then
    SUITE_REDIS_HOST=10.0.2.2
fi

redis_image=docker.io/library/redis@sha256:7f7d30b7fdd09467bac58198a1f166dd69789d348d4fe859cccb20e0cf287fbe
mkdir -p .anybuild/suite
run_dir=$(mktemp -d "$PWD/.anybuild/suite/redis.XXXXXX")
container="wasmopticon-fastapi-redis-${run_dir##*.}"
cleanup() {
    local status=$?
    timeout -k 2 5 sudo docker logs "$container" >"$run_dir/redis.log" 2>&1 || true
    timeout -k 2 10 sudo docker rm -fv "$container" >/dev/null 2>&1 || true
    if (( status != 0 )); then
        cat -- "$run_dir/container.log" "$run_dir/redis.log" >&2
    fi
    printf 'Redis log: %s/redis.log\n' "$run_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

timeout -k 2 20 sudo docker run --rm --pull=never -d --name "$container" \
    --publish "127.0.0.1:$DB_PORT:6379" --tmpfs /data \
    "$redis_image" redis-server --save '' --appendonly no >"$run_dir/container.log" 2>&1
deadline=$((SECONDS + 20))
until [[ $(timeout -k 1 3 sudo docker exec "$container" redis-cli ping 2>/dev/null) == PONG ]]; do
    if (( SECONDS >= deadline )); then
        echo "Redis readiness deadline expired." >&2
        exit 1
    fi
    sleep 0.25
done

WASMER_BIN="$project/wasmer-with-redis.sh" \
    "$project/../wasix-suite-support/test.sh" "$project" python3 check.py
