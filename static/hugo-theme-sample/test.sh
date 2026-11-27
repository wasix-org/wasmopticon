#!/usr/bin/env bash
set -euo pipefail

wasmer=$(command -v "${WASMER_BIN:-wasmer}") || { echo "Set WASMER_BIN to Wasmer." >&2; exit 1; }
wasmer=$(realpath "$wasmer")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
variant=${1:?Choose mainroad, ink, paper-mod, m10c, or photophobia}
read -r selected root repository rev theme_sha default_port < <(awk -v name="$variant" '$1 == name { print; exit }' themes.tsv) || {
    echo "Unknown theme: $variant" >&2
    exit 2
}
cd -- ".suite/$variant"
package=.anybuild/suite/package.webc
site=.suite/site
[[ -f $package && -f .suite/build.lock ]] || { echo "Run build.sh first." >&2; exit 1; }
exec 9<.suite/build.lock
flock -s 9

# Ask the OS for an available loopback port, or check the explicit port.
port=$(python3 - "${PORT:-$default_port}" <<'PY'
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
    (( status == 0 )) || echo "Request evidence in $PWD/$test_tmp" >&2
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
      ! grep -Fq 'WASIX Hugo Themes' "$test_tmp/body"; do
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

compare_export() {
    cmp -- "$site/$1" "$test_tmp/body"
}

request 200 /
expect_mime text/html
expect_body 'WASIX Hugo Themes'
expect_body 'Rendering Fixtures'
compare_export index.html

request 200 /tags/compatibility/
expect_mime text/html
expect_body 'Rendering Fixtures'
compare_export tags/compatibility/index.html

request 200 /index.xml
python3 - "$test_tmp/body" <<'PY'
import sys
from xml.etree import ElementTree

items = ElementTree.parse(sys.argv[1]).findall("./channel/item")
assert any(
    item.findtext("title") == "Rendering Fixtures"
    and item.findtext("link").endswith("/posts/fixture/")
    for item in items
), "Fixture post missing from RSS"
PY
compare_export index.xml

request 404 /missing-page
expect_mime text/html
compare_export 404.html

case "$variant" in
    mainroad)
        request 200 /posts/fixture/
        expect_body 'thumbnail__image'
        expect_body 'theme-preview.png'
        request 200 /theme-preview.png
        expect_mime image/png
        compare_export theme-preview.png
        ;;
    ink)
        request 200 /css/dark.css
        expect_mime text/css
        expect_body 'background'
        compare_export css/dark.css
        ;;
    paper-mod)
        request 200 /index.json
        expect_mime application/json
        jq -e 'any(.[]; .title == "Rendering Fixtures" and (.permalink | endswith("/posts/fixture/")))' \
            "$test_tmp/body" >/dev/null
        compare_export index.json
        ;;
    m10c)
        styles=("$site"/css/main.min.*.css)
        [[ ${#styles[@]} == 1 && -f ${styles[0]} ]]
        asset=${styles[0]#"$site"/}
        request 200 "/$asset"
        expect_mime text/css
        expect_body 'app-header'
        compare_export "$asset"
        ;;
    photophobia)
        request 200 /posts/fixture/
        expect_body 'Fixture screenshot'
        expect_body 'width=160'
        images=("$site"/fixture_hu*.png)
        [[ ${#images[@]} == 1 && -f ${images[0]} ]]
        asset=${images[0]#"$site"/}
        request 200 "/$asset"
        expect_mime image/png
        compare_export "$asset"
        python3 - "$test_tmp/body" <<'PY'
import struct
import sys
from pathlib import Path

image = Path(sys.argv[1]).read_bytes()
assert image[:8] == b"\x89PNG\r\n\x1a\n"
assert struct.unpack_from(">I", image, 16)[0] == 160
PY
        ;;
esac

printf 'Hugo %s verified. Evidence in %s/%s\n' "$variant" "$PWD" "$test_tmp"
