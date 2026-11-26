#!/usr/bin/env bash
set -euo pipefail

fixture=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
operation=$1
variant=${2:?Choose excalidraw, it-tools, drawdb, minipaint, piskel, or cdn-starter}
case "$variant" in
    excalidraw|it-tools|drawdb|minipaint|piskel|cdn-starter) ;;
    *) echo "Unknown template: $variant" >&2; exit 2 ;;
esac
project="$fixture/.suite/$variant"
if [[ $operation == build ]]; then
    mkdir -p "$project"
    recipe=Anybuild
    [[ $variant != cdn-starter ]] || recipe=Anybuild.cdn
    cp -- "$fixture/$recipe" "$project/Anybuild"
    cp -- "$fixture/$variant.env" "$project/inputs.env"
    export SUITE_NORMALIZE=
    if [[ $variant == excalidraw ]]; then
        export SUITE_NORMALIZE="$fixture/normalize-excalidraw.py"
    fi
fi
exec bash "$fixture/../node-static-support/$operation.sh" "$project"
