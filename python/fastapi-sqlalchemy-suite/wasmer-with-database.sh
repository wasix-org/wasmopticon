#!/usr/bin/env bash
set -euo pipefail

# Supply the mount and guest environment to the common Python test runner.
if [[ "$*" = 'run --help' ]]; then
    exec "$SUITE_WASMER_BIN" "$@"
fi
command=$1
shift
exec "$SUITE_WASMER_BIN" "$command" --volume "$SUITE_SQLITE_STATE:/suite-db" \
    --env SQLITE_PATH=/suite-db/todos.db "$@"
