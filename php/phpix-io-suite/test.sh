#!/usr/bin/env bash
set -euo pipefail

wasmer_bin=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mode=${1:-${PHPIX_IO_MODE:-}}
: "${mode:?usage: test.sh upload|session|outbound [curl|stream|both]}"
workers=1
case "$mode" in
    upload) port=${PORT:-18251} ;;
    session) port=${PORT:-18252}; workers=4 ;;
    outbound)
        port=${PORT:-18253}
        client=${2:-${PHPIX_IO_CLIENT:-both}}
        case "$client" in
            both) clients=(curl stream) ;;
            curl|stream) clients=("$client") ;;
            *) echo 'Outbound client must be curl, stream, or both' >&2; exit 2 ;;
        esac
        ;;
    *) echo "Unknown test mode: $mode" >&2; exit 2 ;;
esac
lane=${WASIX_LANE:-v2}
case "$lane" in
    v1) network=(--net); bind=127.0.0.1:$port; guest_port=$port; upstream_host=127.0.0.1 ;;
    v2) network=(--publish "127.0.0.1:$port:8080"); bind=0.0.0.0:8080; guest_port=8080; upstream_host=10.0.2.2 ;;
    *) echo 'WASIX_LANE must be v1 or v2' >&2; exit 2 ;;
esac

suite=$PWD/.anybuild/suite
package=$suite/package.webc
registry=$suite/registry
[[ -f $package && -d $registry ]] || { echo 'Run build.sh before testing' >&2; exit 1; }
mkdir -p "$suite/runs"
run_dir=$(mktemp -d "$suite/runs/$mode.$lane.XXXXXX")
export WASMER_DIR=${WASMER_DIR:-$suite/wasmer/$lane}
export WASMER_CACHE_DIR=${WASMER_CACHE_DIR:-$WASMER_DIR/cache}
url=http://127.0.0.1:$port
server_pid=
upstream_pid=
cleanup() {
    local status=$?
    for pid in "$server_pid" "$upstream_pid"; do
        [[ -n $pid ]] || continue
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    if (( status != 0 )); then
        tail -n 60 "$run_dir"/*.log >&2 || true
        echo "$mode $lane failed. Evidence in $run_dir" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

app_env=()
if [[ $mode == outbound ]]; then
    python3 upstream.py "$run_dir/upstream.json" "${UPSTREAM_PORT:-18255}" "${TIMEOUT_PORT:-18256}" \
        >"$run_dir/upstream.log" 2>&1 &
    upstream_pid=$!
    deadline=$((SECONDS + 10))
    until [[ -s $run_dir/upstream.json ]]; do
        kill -0 "$upstream_pid" 2>/dev/null && (( SECONDS < deadline )) || exit 1
        sleep 0.1
    done
    upstream_port=$(jq -er '.http' "$run_dir/upstream.json")
    timeout_port=$(jq -er '.timeout' "$run_dir/upstream.json")
    # The inbound stream needs outbound permission for its loopback peer.
    filter="--net=ipv4:allow=$upstream_host:*/out,ipv4:allow=*:$guest_port/in"
    if [[ $lane == v1 ]]; then
        network=("$filter")
    else
        network+=("$filter")
    fi
    app_env=(--env "UPSTREAM_HOST=$upstream_host" --env "UPSTREAM_PORT=$upstream_port" --env "TIMEOUT_PORT=$timeout_port")
fi

curl_local() {
    curl --noproxy '*' --silent --show-error --max-time 25 "$@"
}
timeout --kill-after=5s "${SERVER_TIMEOUT:-105}" \
    "$wasmer_bin" run "$package" --cranelift --offline --include-webc "$registry" \
    "${network[@]}" --entrypoint local --env PHP_INI_SCAN_DIR=/opt/assets \
    --env "PHPIX_PHP_THREADS=$workers" "${app_env[@]}" -- -S "$bind" -t /app/app \
    -d upload_max_filesize=20M -d post_max_size=24M -d session.save_path=/tmp \
    >"$run_dir/server.log" 2>&1 &
server_pid=$!

deadline=$((SECONDS + ${READY_TIMEOUT:-75}))
until curl_local --max-time 1 --fail "$url/" >"$run_dir/index" 2>/dev/null &&
    grep -Fxq 'PHPix I/O suite' "$run_dir/index"; do
    kill -0 "$server_pid" 2>/dev/null && (( SECONDS < deadline )) || {
        echo 'PHPix readiness response missing' >&2
        exit 1
    }
    sleep 0.25
done

case "$mode" in
    upload)
        size=$((20 * 1024 * 1024))
        python3 - "$run_dir/input.bin" "$size" <<'PY'
import random
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(random.Random(510).randbytes(int(sys.argv[2])))
PY
        digest=$(sha256sum "$run_dir/input.bin" | cut -d' ' -f1)
        [[ $(curl_local -H 'Expect:' -F "payload=@$run_dir/input.bin" \
            -o "$run_dir/upload.json" -w '%{http_code}' "$url/upload.php") == 200 ]]
        jq -e --argjson size "$size" --arg digest "$digest" \
            '.size == $size and .sha256 == $digest' "$run_dir/upload.json" >/dev/null
        curl_local --fail -D "$run_dir/download.headers" "$url/download.php" >"$run_dir/download.bin"
        grep -iq '^content-type: application/octet-stream' "$run_dir/download.headers"
        grep -iq '^content-disposition: attachment; filename="suite-upload.bin"' "$run_dir/download.headers"
        cmp "$run_dir/input.bin" "$run_dir/download.bin"
        printf '%s  %s\n' "$digest" "$run_dir/download.bin" | sha256sum --check
        printf x >>"$run_dir/input.bin"
        [[ $(curl_local -H 'Expect:' -F "payload=@$run_dir/input.bin" \
            -o "$run_dir/too-large.json" -w '%{http_code}' "$url/upload.php") == 413 ]]
        jq -e '.upload_error == 1' "$run_dir/too-large.json" >/dev/null
        curl_local --fail "$url/download.php" -o "$run_dir/download.bin"
        printf '%s  %s\n' "$digest" "$run_dir/download.bin" | sha256sum --check
        rm -- "$run_dir/input.bin" "$run_dir/download.bin"
        ;;
    session)
        python3 session-check.py "$port" | tee "$run_dir/session.log"
        ;;
    outbound)
        for client in "${clients[@]}"; do
            for scenario in ok timeout; do
                echo "Checking $client $scenario"
                curl_local --max-time 7 --fail "$url/outbound.php?client=$client&case=$scenario" >"$run_dir/$client-$scenario.json"
                jq -c . "$run_dir/$client-$scenario.json"
            done
            if [[ $client == curl ]]; then
                jq -e '.ok and .status == 200 and .body == "PHPix loopback upstream\n"' "$run_dir/curl-ok.json" >/dev/null
                jq -e '(.ok | not) and .error == 28 and .status == 0 and .elapsed_ms >= 350 and .elapsed_ms <= 2500' \
                    "$run_dir/curl-timeout.json" >/dev/null
            else
                jq -e '.ok and (.status_line | contains(" 200 ")) and .body == "PHPix loopback upstream\n"' "$run_dir/stream-ok.json" >/dev/null
                jq -e '(.ok | not) and (.error == 110 or (.message | test("timed out"; "i"))) and
                    .elapsed_ms >= 350 and .elapsed_ms <= 2500' "$run_dir/stream-timeout.json" >/dev/null
            fi
        done
        ;;
esac
printf '%s %s passed. Evidence in %s\n' "$mode" "$lane" "$run_dir"
