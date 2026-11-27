#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
base=https://raw.githubusercontent.com/wasmerio/examples/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-semantic-search
inputs=$project/.anybuild/inputs
mkdir -p -- "$inputs/model"

tmp=
trap 'if [[ -n "$tmp" ]]; then rm -f -- "$tmp"; fi' EXIT
while read -r sha path; do
    file=$inputs/$path
    if ! sha256sum --check --status <<< "$sha  $file"; then
        tmp=$(mktemp "$file.XXXXXX")
        curl -q -fLSs --retry 2 --max-time 90 "$base/$path" -o "$tmp"
        sha256sum --check <<< "$sha  $tmp"
        mv -f -- "$tmp" "$file"
        tmp=
    fi
done < "$project/inputs.sha256"

exec "$project/../wasix-suite-support/build.sh" "$project" --reproducible
