#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
exec "$project/../wasix-suite-support/test.sh" "$project" python3 check.py
