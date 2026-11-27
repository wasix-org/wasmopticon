#!/usr/bin/env bash
set -euo pipefail

if [[ $# = 2 && $1 = run && $2 = --help ]]; then
    exec "$SUITE_WASMER_BIN" "$@"
fi

command=$1
shift
args=()
for arg in "$@"; do
    if [[ $arg != --net ]]; then
        args+=("$arg")
    fi
done

# Inbound accept checks the peer's ephemeral port against the outbound rules.
network="ipv4:allow=$SUITE_DB_HOST:$DB_PORT/out,ipv4:allow=*:$PORT/in,ipv4:allow=$SUITE_DB_HOST:*/out"
exec "$SUITE_WASMER_BIN" "$command" "--net=$network" \
    --env "DB_HOST=$SUITE_DB_HOST" --env "DB_PORT=$DB_PORT" --env DB_NAME=django \
    --env DB_USERNAME=django --env DB_PASSWORD=fixture-db "${args[@]}"
