#!/usr/bin/env bash
set -euo pipefail

wasmer_bin=$(command -v "${WASMER_BIN:-wasmer}")
wasmer_bin=$(realpath -- "$wasmer_bin")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

lane=${WASIX_LANE:-v2}
port=${PORT:-18140}
workers=${WORKERS:-1}
case "$lane" in
    v1) network=(--net); bind=127.0.0.1:$port ;;
    v2) network=(--publish "127.0.0.1:$port:8080"); bind=0.0.0.0:8080 ;;
    *) echo 'WASIX_LANE must be v1 or v2' >&2; exit 2 ;;
esac
case "$workers" in
    1|4) ;;
    *) echo 'WORKERS must be 1 or 4' >&2; exit 2 ;;
esac

suite=$PWD/.anybuild/suite
package=$suite/package.webc
registry=$suite/registry
[[ -f $package && -d $registry ]] || { echo 'Run build.sh before testing' >&2; exit 1; }
mkdir -p "$suite/runs"
run_dir=$(mktemp -d "$suite/runs/$lane.w$workers.XXXXXX")
export WASMER_DIR=${WASMER_DIR:-$suite/wasmer/$lane}
export WASMER_CACHE_DIR=${WASMER_CACHE_DIR:-$WASMER_DIR/cache}
url=http://127.0.0.1:$port
server_pid=
cleanup() {
    local status=$?
    if [[ -n $server_pid ]]; then
        kill -TERM "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    if (( status != 0 )); then
        tail -n 80 "$run_dir/server.log" >&2
        echo "PHPix $lane failed, evidence in $run_dir" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

curl_local() {
    curl --noproxy '*' --silent --show-error --max-time 5 "$@"
}
timeout --kill-after=5s "${SERVER_TIMEOUT:-3600}" \
    "$wasmer_bin" run "$package" --cranelift --offline --include-webc "$registry" \
    "${network[@]}" --entrypoint local --env PHP_INI_SCAN_DIR=/opt/assets \
    --env "PHPIX_PHP_THREADS=$workers" -- -S "$bind" -t /app/app \
    >"$run_dir/server.log" 2>&1 &
server_pid=$!

deadline=$((SECONDS + ${READY_TIMEOUT:-180}))
until curl_local --fail "$url/" >"$run_dir/index" 2>/dev/null &&
    grep -Fq 'PHP code tester Sandbox Online' "$run_dir/index" &&
    grep -Eq 'PHP Version.*8\.4\.' "$run_dir/index"; do
    kill -0 "$server_pid" 2>/dev/null && (( SECONDS < deadline )) || {
        echo 'PHP 8.4 readiness response missing' >&2
        exit 1
    }
    sleep 0.25
done

assert_roundtrip() {
    local payload=$1
    local body
    body=$(curl_local --fail --data-binary "$payload" "$url/roundtrip.php")
    [[ $body == "roundtrip:$payload" ]]
}

assert_roundtrip 'WASIX PHPix suite'
[[ $(curl_local -o "$run_dir/missing" -w '%{http_code}' "$url/no-such-file.txt") == 404 ]]
[[ $(curl_local -D "$run_dir/method.headers" -o /dev/null -w '%{http_code}' "$url/roundtrip.php") == 405 ]]
grep -iq '^allow: POST' "$run_dir/method.headers"

pids=()
for i in {1..8}; do
    assert_roundtrip "parallel-$i" &
    pids+=("$!")
done
parallel_status=0
for pid in "${pids[@]}"; do
    wait "$pid" || parallel_status=1
done
(( parallel_status == 0 ))

if (( $# )); then
    TARGET_URL=$url "$@"
fi
assert_roundtrip 'readiness after requests'
printf 'PHPix %s workers=%s passed. Evidence in %s\n' "$lane" "$workers" "$run_dir"
