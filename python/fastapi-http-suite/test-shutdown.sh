#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
cd -- "$project"
exec python3 check-shutdown.py
