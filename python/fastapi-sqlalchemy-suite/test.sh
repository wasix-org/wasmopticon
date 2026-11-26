#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
cd -- "$project"
mkdir -p .anybuild/suite
state=$(mktemp -d "$project/.anybuild/suite/sqlite.XXXXXX")
trap 'rm -rf -- "$state"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

export SUITE_WASMER_BIN
SUITE_WASMER_BIN=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
export SUITE_SQLITE_STATE="$state"
export WASMER_BIN="$project/wasmer-with-database.sh"
support="$project/../wasix-suite-support/test.sh"
"$support" "$project" python3 check.py write "$state/expected.json"
test -s "$state/todos.db"
"$support" "$project" python3 check.py verify "$state/expected.json"
