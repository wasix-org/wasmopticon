#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
cd -- "$project"
mkdir -p .anybuild/suite
state=$(mktemp -d "$project/.anybuild/suite/jobs.XXXXXX")
trap 'rm -rf -- "$state"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

export SUITE_WASMER_BIN
SUITE_WASMER_BIN=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
export SUITE_JOB_STATE="$state"
export WASMER_BIN="$project/wasmer-with-state.sh"
"$project/../wasix-suite-support/test.sh" "$project" python3 check.py "$state/interval-jobs.db"
