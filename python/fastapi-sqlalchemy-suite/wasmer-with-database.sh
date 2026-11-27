#!/usr/bin/env bash
set -euo pipefail

# Supply the mount and guest environment to the common Python test runner.
if [[ "$*" = 'run --help' ]]; then
    exec "$SUITE_WASMER_BIN" "$@"
fi
command=$1
shift
case "$SUITE_SQLITE_MOUNT" in
    volume) mount=(--volume "$SUITE_SQLITE_STATE:/suite-db") ;;
    mapdir) mount=(--mapdir "/suite-db:$SUITE_SQLITE_STATE") ;;
    *) echo "Unknown SQLite mount option: $SUITE_SQLITE_MOUNT" >&2; exit 2 ;;
esac
exec "$SUITE_WASMER_BIN" "$command" "${mount[@]}" \
    --env SQLITE_PATH=/suite-db/todos.db "$@"
