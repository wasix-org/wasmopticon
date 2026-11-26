#!/usr/bin/env bash
set -euo pipefail

project=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
cd -- "$project"
sha256sum --check samples.sha256
input_dir=$project/.anybuild/inputs
mkdir -p -- "$input_dir"
rev=993bf9a55d3da307c5f2ecf4f4d716c63f44b764
source_url=https://raw.githubusercontent.com/wasmerio/examples/$rev/python-onnx-image-classifier/model

fetch_model_input() (
    local file=$1 digest=$2 target tmp
    target=$input_dir/$file
    if [[ -f "$target" ]] && sha256sum --check --status <<< "$digest  $target"; then
        return
    fi
    tmp=$(mktemp "$input_dir/.$file.XXXXXX")
    trap 'rm -f -- "$tmp"' EXIT
    curl -q -fLSs --max-time 60 "$source_url/$file" -o "$tmp"
    sha256sum --check <<< "$digest  $tmp"
    mv -f -- "$tmp" "$target"
)

fetch_model_input mobilenetv2-12.onnx c0c3f76d93fa3fd6580652a45618618a220fced18babf65774ed169de0432ad5
fetch_model_input synset.txt acf75ef0abe89694b19056e0796401068b459c457baa30335f240c7692857355
exec "$project/../wasix-suite-support/build.sh" "$project" --reproducible
