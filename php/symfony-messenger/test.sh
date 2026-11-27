#!/usr/bin/env bash
set -euo pipefail

wasmer_bin=$(command -v "${WASMER_BIN:-wasmer}")
wasmer_bin=$(realpath -- "$wasmer_bin")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

lane=${WASIX_LANE:-v2}
port=${PORT:-18261}
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
mkdir "$run_dir/state"
touch "$run_dir/state/queue.sqlite"
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
        tail -n 80 "$run_dir"/*.log >&2 || true
        echo "symfony-messenger $lane failed, evidence in $run_dir" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

curl_local() {
    curl --noproxy '*' --silent --show-error --max-time 8 "$@"
}
runtime=("$wasmer_bin" run "$package" --cranelift --offline --include-webc "$registry"
    --volume "$run_dir/state:/suite" --env PHP_INI_SCAN_DIR=/opt/assets --env PHPIX_PHP_THREADS=1
    --env APP_ENV=prod --env APP_DEBUG=0 --env SUITE_DB_PATH=/suite/queue.sqlite)
guest_cli() {
    timeout --kill-after=5s "${GUEST_TIMEOUT:-35}" "${runtime[@]}" --entrypoint local-php -- "$@"
}

timeout --kill-after=5s "${SERVER_TIMEOUT:-115}" "${runtime[@]}" "${network[@]}" \
    --entrypoint local -- -S "$bind" -t /app/public >"$run_dir/server.log" 2>&1 &
server_pid=$!
deadline=$((SECONDS + ${READY_TIMEOUT:-60}))
until curl_local --max-time 1 --fail "$url/" >"$run_dir/index" 2>/dev/null &&
    grep -Fq "Your Symfony app is live on Wasmer Edge" "$run_dir/index"; do
    kill -0 "$server_pid" 2>/dev/null && (( SECONDS < deadline )) || {
        echo 'Starter readiness response missing' >&2
        exit 1
    }
    sleep 0.25
done

for message in fixture-1 fixture-2 fixture-3; do
    [[ $(curl_local -o "$run_dir/$message.json" -w '%{http_code}' --data-urlencode "value=$message" "$url/suite/dispatch") == 202 ]]
    jq -e '.queued == true' "$run_dir/$message.json" >/dev/null
done
curl_local --fail "$url/suite/results" >"$run_dir/before.json"
jq -e '.pending == 3 and .handled == []' "$run_dir/before.json" >/dev/null
# Symfony Runtime needs SCRIPT_FILENAME, which the PHPix CLI leaves empty.
guest_cli -r '$_SERVER["SCRIPT_FILENAME"] = "/app/bin/console"; require $_SERVER["SCRIPT_FILENAME"];' -- \
    messenger:consume fixture --limit=3 --time-limit=15 --no-interaction >"$run_dir/consumer.log" 2>&1
curl_local --fail "$url/suite/results" >"$run_dir/after.json"
jq -e '.pending == 0 and .handled == ["fixture-1", "fixture-2", "fixture-3"]' "$run_dir/after.json" >/dev/null
printf 'symfony-messenger %s passed. Evidence in %s\n' "$lane" "$run_dir"
