#!/usr/bin/env bash
set -euo pipefail

wasmer=$(command -v "${WASMER_BIN:-wasmer}") || { echo "Set WASMER_BIN to Wasmer." >&2; exit 1; }
wasmer=$(realpath "$wasmer")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
package=.anybuild/suite/package.webc
[[ -f "$package" ]] || { echo "Run build.sh first." >&2; exit 1; }

# Ask the OS for an available loopback port, or check the explicit port.
port=$(python3 - "${PORT:-}" <<'PY'
import socket
import sys

port = int(sys.argv[1]) if sys.argv[1] else 0
if sys.argv[1] and not 1 <= port <= 65535:
    sys.exit("PORT must be in 1..65535")
with socket.socket() as listener:
    listener.bind(("127.0.0.1", port))
    print(listener.getsockname()[1])
PY
)
url="http://127.0.0.1:$port"
timeout=${READY_TIMEOUT:-120}
[[ "$timeout" =~ ^[1-9][0-9]*$ ]] || { echo "READY_TIMEOUT must be a positive integer." >&2; exit 1; }

run_help=$("$wasmer" run --help)
network=(--net)
guest_host=127.0.0.1
if [[ "$run_help" == *'--publish <'* ]]; then
    network=(--publish "127.0.0.1:$port:$port")
    guest_host=0.0.0.0
fi

test_tmp=$(mktemp -d .anybuild/suite/test.XXXXXX)
server_pid=
cleanup() {
    local status=$?
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        for _ in {1..10}; do
            kill -0 "$server_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    if (( status != 0 )); then
        cat -- "$test_tmp/server.log" >&2
    fi
    rm -rf -- "$test_tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$wasmer" run --cranelift --offline "${network[@]}" \
    --env "SERVER_HOST=$guest_host" --env "SERVER_PORT=$port" \
    "$package" >"$test_tmp/server.log" 2>&1 &
server_pid=$!
deadline=$((SECONDS + timeout))
while ! curl -q --noproxy '*' --max-time 1 -fsS -o "$test_tmp/body" "$url/" 2>/dev/null ||
      ! grep -Fq '<title>15.01 updated</title>' "$test_tmp/body"; do
    if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
        echo "Hugo site failed to become ready at $url." >&2
        exit 1
    fi
    sleep 0.2
done

request() {
    local expected=$1 path=$2 actual
    shift 2
    actual=$(curl -q --noproxy '*' --max-time 5 -sS -D "$test_tmp/headers" \
        -o "$test_tmp/body" -w '%{http_code}' "$@" "$url$path")
    if [[ "$actual" != "$expected" ]]; then
        echo "$path returned HTTP $actual, expected $expected." >&2
        cat -- "$test_tmp/headers" >&2
        exit 1
    fi
    printf '%s %s\n' "$actual" "$path"
}

header() {
    awk -v name="$1" '
        tolower($1) == tolower(name) ":" {
            sub(/^[^:]+:[[:space:]]*/, "")
            sub(/\r$/, "")
            print
        }' "$test_tmp/headers"
}

expect_body() {
    if ! grep -Fq -- "$1" "$test_tmp/body"; then
        printf 'Response is missing %s\n' "$1" >&2
        exit 1
    fi
}

expect_mime() {
    local mime
    mime=$(header Content-Type)
    if [[ "${mime%%;*}" != "$1" ]]; then
        printf "Content-Type was '%s', expected '%s'.\n" "$mime" "$1" >&2
        exit 1
    fi
}

expect_hash() {
    printf '%s  %s\n' "$1" "$test_tmp/body" | sha256sum --check --status || {
        echo "Response body checksum did not match." >&2
        exit 1
    }
}

request 200 /
expect_mime text/html
expect_body '<title>15.01 updated</title>'
expect_body 'href=/posts/my-first-post/'
expect_body 'href=/ananke/css/main.min.css'

request 200 /posts/my-first-post/
expect_mime text/html
expect_body 'My First Post</h1>'
expect_body '<strong>bold</strong>'
expect_body '<em>emphasized</em>'

request 200 /index.xml
expect_body '<rss version="2.0"'
expect_body '<item><title>My First Post</title><link>/posts/my-first-post/</link>'

request 200 /ananke/css/main.min.css
expect_mime text/css
expect_hash 2438bcafd7af9675c426d1a4afcd16cfff18e4e10f401071e45b5ccd3be40a0d

request 200 /images/gohugo-default-sample-hero-image.jpg
expect_mime image/jpeg
expect_hash 23371f1d9b625db30eec783d0e784ceac9034a97645b9492ef6434faab445ba6

request 404 /missing-page
expect_mime text/html
expect_body 'This is not the page you were looking for</h1>'

printf 'Hugo site verified at %s\n' "$url"
