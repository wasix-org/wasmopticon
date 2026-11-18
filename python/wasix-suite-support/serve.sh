#!/usr/bin/env bash
set -euo pipefail

wasmer=$(realpath "$(command -v "${WASMER_BIN:-wasmer}")")
support=$(realpath "$(dirname -- "${BASH_SOURCE[0]}")")
registry=$(realpath "${REGISTRY_DIR:-"$support/.anybuild/registry"}")
while IFS=$'\t' read -r path sha; do
    sha256sum --check --status <<< "$sha  $registry/$path" || {
        echo "Missing or invalid registry input: $registry/$path. Run build.sh." >&2
        exit 1
    }
done < "$support/registry.tsv"
cd -- "$1"
package=.anybuild/suite/package.webc
[[ -f "$package" ]] || { echo "Run build.sh first." >&2; exit 1; }
port=${PORT:?Set PORT to a free loopback port.}
[[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && (( port <= 65535 )) || {
    echo "PORT must be in 1..65535." >&2
    exit 1
}

run_help=$("$wasmer" run --help)
host=127.0.0.1
network=(--net)
if [[ "$run_help" == *'--publish <'* ]]; then
    host=0.0.0.0
    network=(--publish "127.0.0.1:$port:$port")
fi

exec "$wasmer" run --cranelift --offline --include-webc "$registry" "${network[@]}" \
    --env "HOST=$host" --env "PORT=$port" --env PYTHONDONTWRITEBYTECODE=1 \
    --env PYTHONPATH=/app:/opt/venv/lib/python3.13/site-packages "$package"
