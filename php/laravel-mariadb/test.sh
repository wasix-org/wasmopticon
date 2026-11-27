#!/usr/bin/env bash
set -euo pipefail

wasmer_bin=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ./inputs.env

lane=${WASIX_LANE:-v2}
port=${PORT:-18250}
db_port=${DB_PORT:-${MARIADB_PORT:-18254}}
case "$lane" in
    v1) db_host=127.0.0.1; bind=127.0.0.1:$port; guest_port=$port; publish=() ;;
    v2) db_host=10.0.2.2; bind=0.0.0.0:8080; guest_port=8080
        publish=(--publish "127.0.0.1:$port:8080") ;;
    *) echo 'WASIX_LANE must be v1 or v2' >&2; exit 2 ;;
esac

suite=$PWD/.anybuild/suite
package=$suite/package.webc
registry=$suite/registry
[[ -f $package && -d $registry ]] || { echo 'Run build.sh before testing' >&2; exit 1; }
mkdir -p "$suite/runs"
run_dir=$(mktemp -d "$suite/runs/$lane.XXXXXX")
container=wasmopticon-laravel-${run_dir##*/}-$UID
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
    timeout --kill-after=5s 15s sudo docker logs "$container" >"$run_dir/mariadb.log" 2>&1 || true
    timeout --kill-after=5s 20s sudo docker rm --force --volumes "$container" >/dev/null 2>&1 || true
    if (( status != 0 )); then
        tail -n 65 "$run_dir"/*.log >&2 || true
        echo "Laravel MariaDB $lane failed. Evidence in $run_dir" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

timeout --kill-after=5s 100s sudo docker run --detach --pull=missing --name "$container" \
    --publish "127.0.0.1:$db_port:3306" --tmpfs /var/lib/mysql:rw,size=1g \
    -e MARIADB_ROOT_PASSWORD=fixture-root -e MARIADB_USER=laravel \
    -e MARIADB_PASSWORD=fixture-db -e MARIADB_DATABASE=laravel \
    "$MARIADB_IMAGE" >"$run_dir/container.log" 2>&1

deadline=$((SECONDS + 60))
until timeout 5s sudo docker exec "$container" healthcheck.sh --connect --innodb_initialized >"$run_dir/db-health.log" 2>&1; do
    (( SECONDS < deadline )) || { echo 'MariaDB readiness deadline expired' >&2; exit 1; }
    sleep 0.5
done

# The listen policy also checks the host client's ephemeral port on accept.
network=("--net=ipv4:allow=$db_host:$db_port/out,ipv4:allow=*:$guest_port/in,ipv4:allow=$db_host:*/out")
runtime=("$wasmer_bin" run "$package" --cranelift --offline --include-webc "$registry"
    "${network[@]}" --env PHP_INI_SCAN_DIR=/opt/assets --env PHPIX_PHP_THREADS=1
    --env APP_ENV=production --env APP_DEBUG=false --env "APP_URL=$url" --env LOG_CHANNEL=stderr
    --env CACHE_STORE=file --env SESSION_DRIVER=cookie --env QUEUE_CONNECTION=sync
    --env DB_CONNECTION=mariadb --env "DB_HOST=$db_host" --env "DB_PORT=$db_port"
    --env DB_DATABASE=laravel --env DB_USERNAME=laravel --env DB_PASSWORD=fixture-db)

timeout --kill-after=5s "${GUEST_TIMEOUT:-80}" "${runtime[@]}" \
    --entrypoint local-php -- artisan migrate --force --no-interaction >"$run_dir/migrate.log" 2>&1
for migration in create_users_table create_cache_table create_jobs_table; do
    grep -E "$migration.*DONE" "$run_dir/migrate.log" >/dev/null
done

curl_local() {
    curl --noproxy '*' --silent --show-error --max-time 10 "$@"
}
timeout --kill-after=5s "${SERVER_TIMEOUT:-120}" "${runtime[@]}" "${publish[@]}" \
    --entrypoint local -- -S "$bind" -t /app/public >"$run_dir/server.log" 2>&1 &
server_pid=$!

deadline=$((SECONDS + ${READY_TIMEOUT:-75}))
until curl_local --max-time 1 --fail "$url/" >"$run_dir/home" 2>/dev/null &&
    grep -Fq 'Your Laravel app is running' "$run_dir/home"; do
    kill -0 "$server_pid" 2>/dev/null && (( SECONDS < deadline )) || {
        echo 'Laravel readiness response missing' >&2
        exit 1
    }
    sleep 0.25
done

users=$url/suite/users
email=committed@example.test
rolled_back=rolled-back@example.test
[[ $(curl_local -H 'Accept: application/json' -o "$run_dir/write.json" -w '%{http_code}' \
    --data-urlencode 'name=Committed fixture' --data-urlencode "email=$email" "$users") == 201 ]]
curl_local --fail -H 'Accept: application/json' "$users/$email" >"$run_dir/read.json"
jq -e --arg email "$email" '.name == "Committed fixture" and .email == $email' "$run_dir/read.json" >/dev/null

curl_local --fail -H 'Accept: application/json' --data-urlencode 'name=Rollback fixture' \
    --data-urlencode "email=$rolled_back" "$users/rollback" >"$run_dir/rollback.json"
jq -e '.rolled_back == true' "$run_dir/rollback.json" >/dev/null
[[ $(curl_local -H 'Accept: application/json' -o "$run_dir/rolled-back.json" -w '%{http_code}' \
    "$users/$rolled_back") == 404 ]]
curl_local --fail -H 'Accept: application/json' "$users/$email" >"$run_dir/after-rollback.json"
cmp "$run_dir/read.json" "$run_dir/after-rollback.json"

timeout 10s sudo docker exec "$container" mariadb --batch --skip-column-names \
    -ularavel -pfixture-db laravel -e 'SELECT email FROM users ORDER BY email' >"$run_dir/database-rows"
grep -Fxq "$email" "$run_dir/database-rows"
[[ $(wc -l <"$run_dir/database-rows") == 1 ]]
printf 'Laravel MariaDB %s passed. Evidence in %s\n' "$lane" "$run_dir"
