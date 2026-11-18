#!/usr/bin/env bash
set -euo pipefail

wasmer_bin=$(command -v "${WASMER_BIN:-wasmer}")
wasmer_bin=$(realpath -- "$wasmer_bin")
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ./inputs.env

lane=${WASIX_LANE:-v2}
port=${PORT:-18150}
case "$lane" in
    v1) db_host=127.0.0.1; bind=127.0.0.1:$port; guest_port=$port; publish=() ;;
    v2) db_host=10.0.2.2; bind=0.0.0.0:8080; guest_port=8080
        publish=(--publish "127.0.0.1:$port:$guest_port") ;;
    *) echo 'WASIX_LANE must be v1 or v2' >&2; exit 2 ;;
esac

suite=$PWD/.anybuild/suite
package=$suite/package.webc
registry=$suite/registry
[[ -f $package && -d $registry ]] || { echo 'Run build.sh before testing' >&2; exit 1; }
mkdir -p "$suite/runs"
run_dir=$(mktemp -d "$suite/runs/$lane.XXXXXX")
container=wasmopticon-wordpress-${run_dir##*/}-$UID
content=$run_dir/wp-content
mkdir -p "$content/uploads"
cp -- sample.txt "$content/uploads/sample.txt"

export WASMER_DIR=${WASMER_DIR:-$suite/wasmer/$lane}
export WASMER_CACHE_DIR=${WASMER_CACHE_DIR:-$WASMER_DIR/cache}
url=http://127.0.0.1:$port
server_pid=
stop_server() {
    if [[ -n $server_pid ]]; then
        kill -TERM "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
        server_pid=
    fi
}
cleanup() {
    local status=$?
    stop_server
    docker logs "$container" >"$run_dir/mariadb.log" 2>&1 || true
    timeout --kill-after=5s 20s docker rm --force --volumes "$container" >/dev/null 2>&1 || true
    if (( status != 0 )); then
        for log in "$run_dir"/*.log; do
            printf '\n--- %s ---\n' "${log##*/}" >&2
            tail -n 60 "$log" >&2
        done
        echo "WordPress $lane failed, evidence in $run_dir" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

timeout --kill-after=5s 120s docker run --detach --pull=missing --name "$container" \
    --publish 127.0.0.1::3306 --tmpfs /var/lib/mysql:rw,size=1g \
    -e MARIADB_ROOT_PASSWORD=fixture-root -e MARIADB_USER=wordpress \
    -e MARIADB_PASSWORD=fixture-db -e MARIADB_DATABASE=wordpress \
    "$MARIADB_IMAGE" >"$run_dir/container.log" 2>&1
db_endpoint=$(docker port "$container" 3306/tcp)
[[ $db_endpoint =~ ^127\.0\.0\.1:([0-9]+)$ ]]
db_port=${BASH_REMATCH[1]}

deadline=$((SECONDS + 60))
until timeout 5s docker exec "$container" healthcheck.sh --connect --innodb_initialized >"$run_dir/db-health.log" 2>&1; do
    (( SECONDS < deadline )) || { echo 'MariaDB readiness deadline expired' >&2; exit 1; }
    sleep 0.5
done

# Accept checks the loopback client address and its ephemeral port as outbound.
network=("--net=ipv4:allow=$db_host:$db_port/out,ipv4:allow=*:$guest_port/in,ipv4:allow=$db_host:*/out")
runtime=("$wasmer_bin" run "$package" --cranelift --offline --include-webc "$registry"
    "${network[@]}" --volume "$content:/app/wp-content"
    --env "DB_HOST=$db_host" --env "DB_PORT=$db_port" --env DB_NAME=wordpress
    --env DB_USERNAME=wordpress --env DB_PASSWORD=fixture-db --env "WP_SITEURL=$url"
    --env PHP_INI_SCAN_DIR=/opt/assets --env PHPIX_PHP_THREADS=1
    --env WPCONTENT_BASE_PATH=/opt/wpcontent_base --env WP_CONTENT_DIR=/app/wp-content
    --env WP_DEFAULT_THEME=fixture --env 'WP_SITE_TITLE=WASIX WordPress Fixture'
    --env WP_ADMIN_PASSWORD=fixture-admin --env WP_ADMIN_EMAIL=admin@example.test)

guest() {
    timeout --kill-after=5s "${GUEST_TIMEOUT:-120}" "${runtime[@]}" "$@"
}
guest --entrypoint local-php -- -r '
    $db = new mysqli(getenv("DB_HOST"), getenv("DB_USERNAME"), getenv("DB_PASSWORD"),
        getenv("DB_NAME"), (int) getenv("DB_PORT"));
    $result = $db->query("SELECT 123")->fetch_row();
    echo $result[0], PHP_EOL;
' >"$run_dir/db.log" 2>&1
grep -Fxq 123 "$run_dir/db.log"

guest --entrypoint after_deploy >"$run_dir/setup.log" 2>&1
wp() {
    guest --entrypoint wp -- "$@"
}
wp core is-installed >>"$run_dir/setup.log" 2>&1
wp option update permalink_structure '/%postname%/' >>"$run_dir/setup.log" 2>&1
post_id=$(wp post create --post_type=post --post_status=publish --post_name=wasix-fixture \
    '--post_title=WASIX Fixture Post' '--post_content=Persistence fixture body' \
    --porcelain 2>"$run_dir/seed.log")
[[ $post_id =~ ^[0-9]+$ ]]
printf '%s\n' "$post_id" >"$run_dir/post-id"

curl_local() {
    curl --noproxy '*' --silent --show-error --max-time 10 "$@"
}
start_server() {
    local label=$1
    timeout --kill-after=5s "${SERVER_TIMEOUT:-3600}" "${runtime[@]}" \
        "${publish[@]}" --entrypoint local -- -S "$bind" >"$run_dir/$label.log" 2>&1 &
    server_pid=$!
    local deadline=$((SECONDS + ${READY_TIMEOUT:-180}))
    until curl_local --fail "$url/" >"$run_dir/home.html" 2>/dev/null &&
        grep -Fq '<h1>WASIX WordPress Fixture</h1>' "$run_dir/home.html"; do
        kill -0 "$server_pid" 2>/dev/null && (( SECONDS < deadline )) || {
            echo 'WordPress readiness response missing' >&2
            exit 1
        }
        sleep 0.5
    done
}
assert_site() {
    local label=$1
    [[ $(curl_local --output "$run_dir/post-$label.html" --write-out '%{http_code}' \
        "$url/wasix-fixture/") == 200 ]]
    grep -Fq 'Persistence fixture body' "$run_dir/post-$label.html"
    curl_local --fail --get --data-urlencode "rest_route=/wp/v2/posts/$post_id" \
        "$url/index.php" >"$run_dir/post-$label.json"
    jq -e --argjson id "$post_id" \
        '.id == $id and .slug == "wasix-fixture" and .title.rendered == "WASIX Fixture Post"' \
        "$run_dir/post-$label.json" >/dev/null
    curl_local --fail "$url/wp-content/uploads/sample.txt" >"$run_dir/sample-$label.txt"
    cmp -- sample.txt "$run_dir/sample-$label.txt"
}
start_server initial
assert_site initial
stop_server
start_server restart
assert_site restart
if (( $# )); then
    TARGET_URL=$url "$@"
    assert_site after-load
fi
printf 'WordPress %s passed. Evidence in %s\n' "$lane" "$run_dir"
