#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${WASMER_BIN:=wasmer}"
: "${REGISTRY_DIR:?Set REGISTRY_DIR to the local WebC registry root}"
: "${WASIX_LANE:?Set WASIX_LANE to v1 or v2}"
: "${PORT:=18880}"

if [[ ! $PORT =~ ^[1-9][0-9]{0,4}$ ]] || (( PORT > 65535 )); then
  echo "Invalid PORT: $PORT" >&2
  exit 2
fi
package="$PWD/.anybuild/suite/package.webc"
(cd "$REGISTRY_DIR" && sha256sum --strict --quiet -c "$OLDPWD/registry.sha256")
case "$WASIX_LANE" in
  v1) network=(--net --env HONO_HOST=127.0.0.1 --env "PORT=$PORT");;
  v2) network=(--publish "127.0.0.1:$PORT:8080" --env HONO_HOST=0.0.0.0 --env PORT=8080);;
  *) echo "Unknown WASIX_LANE: $WASIX_LANE" >&2; exit 2;;
esac
exec "$WASMER_BIN" run --cranelift --offline --include-webc "$REGISTRY_DIR" \
  "${network[@]}" --entrypoint start "$package"
