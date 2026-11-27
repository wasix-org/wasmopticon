#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" = 'run --help' ]]; then
    exec "$SUITE_WASMER_BIN" "$@"
fi
command=$1
shift
exec "$SUITE_WASMER_BIN" "$command" --volume "$SUITE_JOB_STATE:/suite-state" \
    --env JOB_DB_PATH=/suite-state/interval-jobs.db "$@"
