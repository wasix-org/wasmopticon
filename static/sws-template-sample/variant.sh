#!/usr/bin/env bash
set -euo pipefail

fixture=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
operation=$1
variant=${2:?Choose app-client-side-router, duckdb-csv-explorer, or bentopdf}
case "$variant" in
    app-client-side-router|duckdb-csv-explorer|bentopdf) ;;
    *) echo "Unknown template: $variant" >&2; exit 2 ;;
esac
project="$fixture/.suite/$variant"
if [[ $operation == build ]]; then
    mkdir -p "$project"
    cp -- "$fixture/Anybuild" "$project/"
    cp -- "$fixture/$variant.env" "$project/inputs.env"
fi
exec bash "$fixture/../node-static-support/$operation.sh" "$project"
