#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
input_dir=$project/.anybuild/inputs
mkdir -p -- "$input_dir"
model=$input_dir/tiny-classifier.onnx
sha=ffb0974440daf6fee3f59072a467194d920481b3afb0ff0606e38be0e4ffd3cf
if ! sha256sum --check --status <<< "$sha  $model"; then
    tmp=$(mktemp "$model.XXXXXX")
    trap 'rm -f -- "$tmp"' EXIT
    curl -q -fLSs --max-time 30 \
        https://raw.githubusercontent.com/wasmerio/examples/1da21d1232ce101832921e4d5c8d0a81adc6b98b/python-netron/samples/tiny-classifier.onnx \
        -o "$tmp"
    sha256sum --check <<< "$sha  $tmp"
    mv -f -- "$tmp" "$model"
fi

exec "$project/../wasix-suite-support/build.sh" "$project"
