#!/usr/bin/env bash
set -euo pipefail

support=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
cd -- "$1"
shift
port=$(python3 - "${PORT:-}" <<'PY'
import socket
import sys

given = sys.argv[1]
port = int(given) if given else 0
if given and not 1 <= port <= 65535:
    sys.exit("PORT must be in 1..65535.")
with socket.socket() as listener:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", port))
    print(listener.getsockname()[1])
PY
)
url="http://127.0.0.1:$port"
ready_timeout=${READY_TIMEOUT:-90}
[[ "$ready_timeout" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid READY_TIMEOUT." >&2; exit 1; }

mkdir -p .anybuild/suite
run=$(mktemp -d .anybuild/suite/test.XXXXXX)
PORT=$port "$support/serve.sh" "$PWD" >"$run/server.log" 2>&1 &
server=$!
cleanup() {
    local status=$?
    if kill -TERM "$server" 2>/dev/null; then
        for _ in {1..30}; do
            kill -0 "$server" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL "$server" 2>/dev/null || true
    fi
    wait "$server" 2>/dev/null || true
    if (( status != 0 )); then
        cat "$run/server.log" >&2
    fi
    printf 'Server log: %s/%s/server.log\n' "$PWD" "$run"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

start=$SECONDS
until curl -q --noproxy '*' --max-time 1 -fsS -o /dev/null "$url/"; do
    if ! kill -0 "$server" 2>/dev/null || (( SECONDS - start >= ready_timeout )); then
        echo "Server did not become ready at $url." >&2
        exit 1
    fi
    sleep 0.25
done 2>"$run/readiness.log"
printf 'Ready at %s in %ss\n' "$url" "$((SECONDS - start))"
timeout -k 2 30 "$@" "$url"
