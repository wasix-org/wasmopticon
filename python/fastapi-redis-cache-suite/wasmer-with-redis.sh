#!/usr/bin/env bash
set -euo pipefail

# Pass guest Redis configuration through the common Python test runner.
if [[ "$*" = 'run --help' ]]; then
    exec "$SUITE_WASMER_BIN" "$@"
fi
command=$1
shift
exec "$SUITE_WASMER_BIN" "$command" \
    --env "REDIS_HOST=$SUITE_REDIS_HOST" --env "REDIS_PORT=$DB_PORT" "$@"
