#!/usr/bin/env bash
set -euo pipefail

wasmer_bin=$(command -v "${WASMER_BIN:-wasmer}")
wasmer_bin=$(realpath -- "$wasmer_bin")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

lane=${WASIX_LANE:-v2}
port=${PORT:-18220}
case "$lane" in
    v1) network=(--net); bind=127.0.0.1:$port ;;
    v2) network=(--publish "127.0.0.1:$port:8080"); bind=0.0.0.0:8080 ;;
    *) echo 'WASIX_LANE must be v1 or v2' >&2; exit 2 ;;
esac
suite=$PWD/.anybuild/suite
package=$suite/package.webc
registry=$suite/registry
[[ -f $package && -d $registry ]] || { echo 'Run build.sh before testing' >&2; exit 1; }
mkdir -p "$suite/runs"
run_dir=$(mktemp -d "$suite/runs/$lane.XXXXXX")
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
        echo "Symfony starter $lane failed, evidence in $run_dir" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

curl_local() {
    curl --noproxy '*' --silent --show-error --max-time 5 "$@"
}
app_env=(--env APP_ENV=prod --env APP_DEBUG=0)
timeout --kill-after=5s "${SERVER_TIMEOUT:-120}" \
    "$wasmer_bin" run "$package" --cranelift --offline --include-webc "$registry" \
    "${network[@]}" --entrypoint local --env PHP_INI_SCAN_DIR=/opt/assets \
    --env PHPIX_PHP_THREADS=1 "${app_env[@]}" -- -S "$bind" -t /app/public \
    >"$run_dir/server.log" 2>&1 &
server_pid=$!

deadline=$((SECONDS + ${READY_TIMEOUT:-80}))
until curl_local --fail "$url/" >"$run_dir/index" 2>/dev/null; do
    kill -0 "$server_pid" 2>/dev/null && (( SECONDS < deadline )) || {
        echo 'Starter readiness response missing' >&2
        exit 1
    }
    sleep 0.25
done

grep -Fq 'Your Symfony app is live on Wasmer Edge' "$run_dir/index"
grep -Eq 'Symfony 7\.4\.23 on PHP 8\.4\.' "$run_dir/index"
curl_local --fail -D "$run_dir/hello.headers" "$url/api/hello" >"$run_dir/hello.json"
grep -iq '^content-type: application/json' "$run_dir/hello.headers"
jq -e '.message == "Hello from Symfony on Wasmer Edge" and .symfony == "7.4.23"
       and (.php | startswith("8.4."))' "$run_dir/hello.json" > /dev/null
curl_local --fail "$url/starter-ui.js" >"$run_dir/starter-ui.js"
grep -Fq 'wasmer-card' "$run_dir/starter-ui.js"
[[ $(curl_local -o "$run_dir/missing" -w '%{http_code}' "$url/no-such-route") == 404 ]]
grep -Fq 'Not Found' "$run_dir/missing"
printf 'Symfony starter %s passed. Evidence in %s\n' "$lane" "$run_dir"
