#!/usr/bin/env bash
set -euo pipefail

wasmer_bin=$(command -v "${WASMER_BIN:-wasmer}")
wasmer_bin=$(realpath -- "$wasmer_bin")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

lane=${WASIX_LANE:-v2}
port=${PORT:-18200}
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
        echo "PHP starter $lane failed, evidence in $run_dir" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

curl_local() {
    curl --noproxy '*' --silent --show-error --max-time 5 "$@"
}
timeout --kill-after=5s "${SERVER_TIMEOUT:-120}" \
    "$wasmer_bin" run "$package" --cranelift --offline --include-webc "$registry" \
    "${network[@]}" --entrypoint local --env PHP_INI_SCAN_DIR=/opt/assets \
    --env PHPIX_PHP_THREADS=1 -- -S "$bind" -t /app/app \
    -d opcache.enable=1 -d opcache.enable_cli=1 -d opcache.validate_timestamps=1 \
    -d opcache.revalidate_freq=0 -d opcache.file_update_protection=0 \
    >"$run_dir/server.log" 2>&1 &
server_pid=$!

deadline=$((SECONDS + ${READY_TIMEOUT:-80}))
until curl_local --fail "$url/" >"$run_dir/index" 2>/dev/null &&
    grep -Fq 'PHP code tester Sandbox Online' "$run_dir/index" &&
    grep -Eq 'PHP Version.*8\.4\.' "$run_dir/index"; do
    kill -0 "$server_pid" 2>/dev/null && (( SECONDS < deadline )) || {
        echo 'PHP 8.4 readiness response missing' >&2
        exit 1
    }
    sleep 0.25
done

grep -Fq 'emoji' "$run_dir/index"
grep -Eq '^Random number[[:space:]]+=>[[:space:]]+[1-9][0-9]{2}$' "$run_dir/index"
curl_local --fail "$url/info.php" >"$run_dir/info"
grep -Fq 'PHP Version' "$run_dir/info"
[[ $(curl_local -o "$run_dir/missing" -w '%{http_code}' "$url/no-such-file.txt") == 404 ]]

curl_local --fail "$url/opcache.php" >"$run_dir/opcache-before.json"
for i in {1..20}; do
    curl_local --fail "$url/" > /dev/null
done
curl_local --fail "$url/opcache.php" >"$run_dir/opcache-after.json"
jq -e -n --slurpfile before "$run_dir/opcache-before.json" --slurpfile after "$run_dir/opcache-after.json" '
    $after[0] as $sample |
    $before[0].statistics as $start |
    $sample.statistics as $end |
    {
        mtime: $sample.index_mtime, cached: $sample.index_cached,
        validate_timestamps: $sample.validate_timestamps, revalidate_freq: $sample.revalidate_freq,
        cached_scripts: $end.num_cached_scripts,
        hits: ($end.hits - $start.hits),
        misses: ($end.misses - $start.misses)
    } | . + {hit_rate: (if .hits + .misses > 0 then .hits / (.hits + .misses) else null end)}
' | tee "$run_dir/opcache-summary.json"
jq -e '.mtime == 946684800 and .cached and .validate_timestamps == "1" and
       .revalidate_freq == "0" and .hits >= 20 and .misses == 0' \
    "$run_dir/opcache-summary.json" > /dev/null
printf 'PHP starter %s passed. Evidence in %s\n' "$lane" "$run_dir"
