#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
export READY_TIMEOUT="${READY_TIMEOUT:-180}"
exec "$project/../wasix-suite-support/test.sh" "$project" python3 check.py
