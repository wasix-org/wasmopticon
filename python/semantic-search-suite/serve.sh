#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
exec "$project/../wasix-suite-support/serve.sh" "$project"
