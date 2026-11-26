#!/usr/bin/env bash
set -euo pipefail

cd -- "$1"
source ./inputs.env
wasmer=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
package=.anybuild/suite/package.webc
site=.suite/source/$OUTPUT
[[ -f .suite/build.lock ]] || { echo "Run build.sh first" >&2; exit 1; }
exec 9<.suite/build.lock
flock -s 9
[[ -f $package && -f $site/index.html ]] || { echo 'Run build.sh first' >&2; exit 1; }
port=$(python3 - "${PORT:-$DEFAULT_PORT}" <<'PY'
import socket
import sys

with socket.socket() as listener:
    listener.bind(("127.0.0.1", int(sys.argv[1])))
    print(listener.getsockname()[1])
PY
)
url="http://127.0.0.1:$port"
run_help=$("$wasmer" run --help)
network=(--net)
guest_host=127.0.0.1
if [[ "$run_help" == *'--publish <'* ]]; then
    network=(--publish "127.0.0.1:$port:$port")
    guest_host=0.0.0.0
fi

run=$(mktemp -d .anybuild/suite/run.XXXXXX)
cleanup() {
    local status=$?
    if [[ -n ${server_pid:-} ]]; then
        kill "$server_pid" 2>/dev/null || true
        for _ in {1..10}; do
            kill -0 "$server_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    if (( status != 0 )); then
        tail -60 "$run/server.log" >&2
        printf 'Request evidence in %s/%s\n' "$PWD" "$run" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$wasmer" run --cranelift --offline "${network[@]}" \
    --env "SERVER_HOST=$guest_host" --env "SERVER_PORT=$port" \
    "$package" >"$run/server.log" 2>&1 &
server_pid=$!

curl_local() {
    curl -q --noproxy '*' --max-time 10 -sS "$@"
}

deadline=$((SECONDS + ${READY_TIMEOUT:-70}))
until curl_local --max-time 1 -f "$url/" >"$run/body" 2>/dev/null; do
    if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
        echo "Server did not become ready at $url." >&2
        exit 1
    fi
    sleep 0.2
done

request() {
    local expected=$1 path=$2 actual
    shift 2
    actual=$(curl_local -D "$run/headers" -o "$run/body" -w '%{http_code}' "$@" "$url$path")
    printf '%s %s\n' "$actual" "$path"
    [[ $actual == "$expected" ]] || { printf 'Expected %s\n' "$expected" >&2; return 1; }
}

header() {
    awk -v name="$1" '
        tolower($1) == tolower(name) ":" {
            sub(/^[^:]+:[[:space:]]*/, "")
            sub(/\r$/, "")
            print
        }' "$run/headers"
}

expect_mime() {
    local mime
    mime=$(header Content-Type)
    [[ ${mime%%;*} =~ $1 ]] || { printf 'Unexpected MIME type %s\n' "$mime" >&2; return 1; }
}

request 200 /
expect_mime '^text/html$'
grep -Fq -- "$HOME_MARKER" "$run/body"
if [[ $CONFIG == spa || $CONFIG == router ]]; then
    request 200 "${ROUTE:-/suite/client-route}" -H 'Accept: text/html'
    expect_mime '^text/html$'
    python3 - "$site/${FALLBACK:-index.html}" "$run/body" <<'PY'
import sys
from pathlib import Path

expected, actual = (Path(path).read_bytes() for path in sys.argv[1:])
assert expected.strip() == actual.strip(), "SWS fallback returned different HTML"
PY
else
    if [[ -n $ROUTE ]]; then
        request 200 "$ROUTE"
        expect_mime '^text/html$'
        grep -Fq -- "$ROUTE_MARKER" "$run/body"
    fi
    request 404 /suite/not-found
    expect_mime '^text/html$'
    if [[ -f $site/404.html ]]; then
        cmp "$site/404.html" "$run/body"
    elif [[ -f $site/404/index.html ]]; then
        cmp "$site/404/index.html" "$run/body"
    fi
fi

# Use a substantial emitted JS file so SWS's compression threshold is met.
asset=${ASSET:-$(python3 - "$site" <<'PY'
import sys
from pathlib import Path
from urllib.parse import quote

site = Path(sys.argv[1])
asset = max(site.rglob("*.js"), key=lambda path: (path.stat().st_size, str(path)))
print(quote(asset.relative_to(site).as_posix(), safe="/"))
PY
)}
asset_file=$(python3 - "$site" "$asset" <<'PY'
import sys
from urllib.parse import unquote

print(f"{sys.argv[1]}/{unquote(sys.argv[2])}")
PY
)
request 200 "/$asset" -H 'Accept-Encoding: identity'
expect_mime "${ASSET_MIME:-^(application|text)/(javascript|x-javascript)$}"
cmp "$asset_file" "$run/body"
cache_control=$(header Cache-Control)
[[ $cache_control =~ max-age=[0-9]+ ]] || { printf 'Unexpected cache header %s\n' "$cache_control" >&2; exit 1; }

length=$(wc -c < "$asset_file")
request 200 "/$asset" --head -H 'Accept-Encoding: identity'
[[ $(header Content-Length) == "$length" ]]
[[ $(header Cache-Control) == "$cache_control" ]]

gzip_asset=${GZIP_ASSET:-$asset}
gzip_file=${GZIP_ASSET:+$site/$GZIP_ASSET}
request 200 "/$gzip_asset" -H 'Accept-Encoding: gzip'
[[ $(header Content-Encoding) == gzip ]]
gzip -dc "$run/body" | cmp "${gzip_file:-$asset_file}" -
printf 'Asset %s, %s bytes, cache %s, gzip verified. Evidence in %s/%s\n' \
    "$asset" "$length" "$cache_control" "$PWD" "$run"

case ${EXTRA:-} in
    wasm)
        wasm=$(find "$site" -name 'duckdb-mvp-*.wasm' -print -quit)
        [[ -f $wasm && $(wc -c < "$wasm") -ge 1048576 ]]
        path="/${wasm#"$site"/}"
        request 200 "$path" --head
        expect_mime '^application/wasm$'
        [[ $(header Content-Length) == "$(wc -c < "$wasm")" ]]
        request 206 "$path" --range 0-4095
        expect_mime '^application/wasm$'
        [[ $(header Content-Range) == "bytes 0-4095/$(wc -c < "$wasm")" ]]
        cmp -n 4096 "$wasm" "$run/body"
        [[ $(wc -c < "$run/body") == 4096 ]]
        ;;
    many-files)
        count=$(find "$site" -type f -printf . | wc -c)
        (( count >= 100 ))
        printf '%s files in export\n' "$count"
        mapfile -t files < <(find "$site" -name '*.html' -print | LC_ALL=C sort)
        (( ${#files[@]} >= 12 ))
        for file in "${files[@]:0:12}"; do
            request 200 "/${file#"$site"/}"
            expect_mime '^text/html$'
            cmp "$file" "$run/body"
        done
        ;;
esac
