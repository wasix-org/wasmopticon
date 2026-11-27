#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
cd -- "$project"
export PORT=${PORT:-18140} DB_PORT=${DB_PORT:-18160}
if [[ ! $PORT =~ ^[1-9][0-9]{0,4}$ || ! $DB_PORT =~ ^[1-9][0-9]{0,4}$ ]] ||
    (( PORT > 65535 || DB_PORT > 65535 || PORT == DB_PORT )); then
    echo "PORT and DB_PORT must be different ports in 1..65535." >&2
    exit 2
fi

export SUITE_WASMER_BIN
SUITE_WASMER_BIN=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
lane=${WASIX_LANE:-}
if [[ -z $lane ]]; then
    run_help=$("$SUITE_WASMER_BIN" run --help)
    if [[ "$run_help" == *'--publish <'* ]]; then lane=v2; else lane=v1; fi
fi
case "$lane" in
    v1) export SUITE_DB_HOST=127.0.0.1 ;;
    v2) export SUITE_DB_HOST=10.0.2.2 ;;
    *) echo "WASIX_LANE must be v1 or v2." >&2; exit 2 ;;
esac

docker=("${DOCKER_BIN:-docker}")
if [[ -z ${DOCKER_BIN:-} ]] && ! timeout -k 2 8 docker info >/dev/null 2>&1; then
    docker=(sudo -n docker)
fi
[[ -f .anybuild/suite/package.webc ]] || { echo "Run build.sh first." >&2; exit 1; }
mkdir -p .anybuild/suite
run=$(mktemp -d .anybuild/suite/mariadb.XXXXXX)
container=wasmopticon-django-mariadb-${run##*.}-$UID
image=docker.io/library/mariadb@sha256:5e73baf8179b29f115101bb102763a47a017361f3e9792daccba6646c3ab1532

cleanup() {
    local status=$?
    timeout -k 2 10 "${docker[@]}" logs "$container" >"$run/mariadb.log" 2>&1 || true
    timeout -k 2 15 "${docker[@]}" rm --force --volumes "$container" >/dev/null 2>&1 || true
    if (( status != 0 )); then
        tail -n 50 "$run/"*.log >&2 || true
    fi
    printf 'MariaDB evidence: %s/%s\n' "$PWD" "$run"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

timeout -k 5 75 "${docker[@]}" run --detach --pull=missing --name "$container" \
    --publish "127.0.0.1:$DB_PORT:3306" --tmpfs /var/lib/mysql:rw,size=512m \
    -e MARIADB_ROOT_PASSWORD=fixture-root -e MARIADB_USER=django \
    -e MARIADB_PASSWORD=fixture-db -e MARIADB_DATABASE=django "$image" >"$run/container.log" 2>&1

deadline=$((SECONDS + 45))
until timeout -k 2 5 "${docker[@]}" exec "$container" healthcheck.sh --connect --innodb_initialized \
    >"$run/db-health.log" 2>&1; do
    (( SECONDS < deadline )) || { echo "MariaDB readiness deadline expired." >&2; exit 1; }
    sleep 0.5
done

WASMER_BIN="$project/wasmer-with-mariadb.sh" "$project/../wasix-suite-support/test.sh" \
    "$project" python3 check.py

timeout -k 2 10 "${docker[@]}" exec "$container" mariadb --batch --skip-column-names \
    -udjango -pfixture-db django -e "
        SELECT COUNT(*) FROM django_migrations WHERE app='auth' AND name='0001_initial';
        SELECT name FROM auth_group ORDER BY name;
    " >"$run/database-rows"
[[ $(cat "$run/database-rows") == $'1\nCommitted fixture' ]]
echo "Verified auth migration and exact committed row directly in MariaDB"
