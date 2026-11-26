#!/usr/bin/env bash
set -euo pipefail

wasmer_bin=$(command -v "${WASMER_BIN:-wasmer}")
wasmer_bin=$(realpath -- "$wasmer_bin")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

lane=${WASIX_LANE:-v2}
port=${PORT:-18210}
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
        echo "Laravel starter $lane failed, evidence in $run_dir" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

curl_local() {
    curl --noproxy '*' --silent --show-error --max-time 5 "$@"
}
app_env=(
    --env APP_ENV=production --env APP_DEBUG=false
    --env APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
    --env "APP_URL=$url" --env LOG_CHANNEL=stderr
    --env SESSION_DRIVER=cookie --env CACHE_STORE=file --env QUEUE_CONNECTION=sync
    --env DB_CONNECTION=sqlite --env DB_DATABASE=/tmp/starter.sqlite
)
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

grep -Fq 'Your Laravel app is running' "$run_dir/index"
grep -Fq "src=\"$url/wasmer-starter-ui.js\"" "$run_dir/index"
curl_local --fail "$url/api/status" >"$run_dir/status.json"
jq -e '.status == "ok" and .framework == "Laravel" and .version == "13.42.0"
       and (.php | startswith("8.4."))' "$run_dir/status.json" > /dev/null
curl_local --fail "$url/up" >"$run_dir/health"
grep -Fq 'Application up' "$run_dir/health"
[[ $(curl_local -o "$run_dir/missing" -w '%{http_code}' "$url/no-such-route") == 404 ]]
grep -Fq 'Not Found' "$run_dir/missing"

cookies=$run_dir/cookies
curl_local --fail -c "$cookies" "$url/suite/form" >"$run_dir/form"
token=$(sed -n 's/.*name="_token" value="\([[:alnum:]]*\)".*/\1/p' "$run_dir/form")
[[ $token =~ ^[[:alnum:]]{40}$ ]]
[[ $(curl_local -b "$cookies" --data-urlencode 'name=must be rejected' \
    -o "$run_dir/rejected" -w '%{http_code}' "$url/suite/form") == 419 ]]

name='WASIX SQLite & Blade'
[[ $(curl_local -b "$cookies" -c "$cookies" -D "$run_dir/post.headers" \
    --data-urlencode "_token=$token" --data-urlencode "name=$name" \
    -o "$run_dir/post" -w '%{http_code}' "$url/suite/form") == 302 ]]
grep -Fiq "location: $url/suite/form" "$run_dir/post.headers"

curl_local --fail -b "$cookies" "$url/suite/form" >"$run_dir/session"
email=$(sed -n 's|.*id="session-email">\([^<]*\)</p>.*|\1|p' "$run_dir/session")
[[ $email =~ ^[0-9a-f]{16}@suite\.example$ ]]
curl_local --fail -b "$cookies" "$url/suite/entry" >"$run_dir/entry.json"
jq -e --arg name "$name" --arg email "$email" \
    '.name == $name and .email == $email' "$run_dir/entry.json" > /dev/null
[[ $(curl_local -o "$run_dir/missing-session" -w '%{http_code}' "$url/suite/entry") == 404 ]]
printf 'Laravel starter %s passed. Evidence in %s\n' "$lane" "$run_dir"
