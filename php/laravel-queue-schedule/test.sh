#!/usr/bin/env bash
set -euo pipefail

wasmer_bin=$(command -v "${WASMER_BIN:-wasmer}")
wasmer_bin=$(realpath -- "$wasmer_bin")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

lane=${WASIX_LANE:-v2}
port=${PORT:-18260}
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
        echo "laravel-queue-schedule $lane failed, evidence in $run_dir" >&2
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
    --env APP_ENV=production --env APP_DEBUG=false --env CACHE_STORE=database
    --env DB_CONNECTION=sqlite --env DB_DATABASE=/suite/queue.sqlite --env QUEUE_CONNECTION=database
    --env LOG_CHANNEL=stderr)
guest_cli() {
    timeout --kill-after=5s "${GUEST_TIMEOUT:-35}" "${runtime[@]}" --entrypoint local-php -- "$@"
}
guest_cli artisan migrate --force --no-interaction >"$run_dir/migrate.log" 2>&1
grep -E 'create_jobs_table.*DONE' "$run_dir/migrate.log" >/dev/null
grep -E 'create_cache_table.*DONE' "$run_dir/migrate.log" >/dev/null

timeout --kill-after=5s "${SERVER_TIMEOUT:-115}" "${runtime[@]}" "${network[@]}" \
    --entrypoint local -- -S "$bind" -t /app/public >"$run_dir/server.log" 2>&1 &
server_pid=$!
deadline=$((SECONDS + ${READY_TIMEOUT:-60}))
until curl_local --max-time 1 --fail "$url/" >"$run_dir/index" 2>/dev/null &&
    grep -Fq "Your Laravel app is running" "$run_dir/index"; do
    kill -0 "$server_pid" 2>/dev/null && (( SECONDS < deadline )) || {
        echo 'Starter readiness response missing' >&2
        exit 1
    }
    sleep 0.25
done

[[ $(curl_local -o "$run_dir/dispatch.json" -w '%{http_code}' --data-urlencode 'value=queued Laravel job' "$url/suite/dispatch") == 202 ]]
jq -e '.queued == true' "$run_dir/dispatch.json" >/dev/null
curl_local --fail "$url/suite/results" >"$run_dir/before.json"
jq -e '.pending == 1 and .handled == null and .scheduled == null' "$run_dir/before.json" >/dev/null
guest_cli artisan queue:work database --once --tries=1 --no-interaction >"$run_dir/consumer.log" 2>&1
curl_local --fail "$url/suite/results" >"$run_dir/handled.json"
jq -e '.pending == 0 and .handled == "queued Laravel job" and .scheduled == null' "$run_dir/handled.json" >/dev/null
guest_cli artisan schedule:run --no-interaction >"$run_dir/scheduler.log" 2>&1
grep -Fq 'suite-scheduled' "$run_dir/scheduler.log"
curl_local --fail "$url/suite/results" >"$run_dir/after.json"
jq -e '.pending == 0 and .handled == "queued Laravel job" and .scheduled == "scheduler ran"' "$run_dir/after.json" >/dev/null
printf 'laravel-queue-schedule %s passed. Evidence in %s\n' "$lane" "$run_dir"
