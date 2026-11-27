#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${WASMER_BIN:=wasmer}"
: "${REGISTRY_DIR:?Set REGISTRY_DIR to the local WebC registry root}"
: "${WASIX_LANE:?Set WASIX_LANE to v1 or v2}"
: "${PORT:=18374}"
: "${DB_PORT:=18375}"

postgres_image=docker.io/library/postgres@sha256:58b1ad1807d86ca43d0e37fded9f0a899a7ab8763fa9576a63059a52de223e1b
package="$PWD/.anybuild/suite/package.webc"
registry_checksums="$PWD/registry.sha256"
(cd "$REGISTRY_DIR" && sha256sum --strict --quiet -c "$registry_checksums")
mkdir -p .anybuild/suite
run_dir=$(mktemp -d "$PWD/.anybuild/suite/functional.${WASIX_LANE}.XXXXXX")
export WASMER_DIR="$run_dir/state"
export WASMER_CACHE_DIR="${WASMER_CACHE_DIR:-$run_dir/cache}"
echo "Functional evidence: $run_dir"

case "$WASIX_LANE" in
  v1)
    db_host=127.0.0.1
    listen=(--env HOST=127.0.0.1 --env "PORT=$PORT")
    serve_network=(--net)
    ;;
  v2)
    db_host=10.0.2.2
    listen=(--env HOST=0.0.0.0 --env PORT=8080)
    serve_network=(--net --publish "127.0.0.1:$PORT:8080")
    ;;
  *) echo "Unknown WASIX_LANE: $WASIX_LANE" >&2; exit 2;;
esac

python3 - "$PORT" "$DB_PORT" <<'PY'
import socket
import sys

with socket.socket() as app, socket.socket() as database:
    app.bind(("127.0.0.1", int(sys.argv[1])))
    database.bind(("127.0.0.1", int(sys.argv[2])))
PY

container="wasmopticon-node-pg-${run_dir##*.}"
server_pid=
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n $server_pid ]]; then
    kill "$server_pid" 2>/dev/null || true
    for ((attempt = 0; attempt < 30; attempt++)); do
      if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    kill -KILL "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  timeout -k 2 10 sudo docker rm -fv "$container" >/dev/null 2>&1 || true
  if (( status != 0 )); then
    for log in postgres server; do
      if [[ -f "$run_dir/$log.log" ]]; then cat "$run_dir/$log.log" >&2; fi
    done
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

timeout -k 2 20 sudo docker run --rm --pull=never -d --name "$container" \
  -e POSTGRES_DB=todos -e POSTGRES_PASSWORD=postgres \
  -p "127.0.0.1:$DB_PORT:5432" "$postgres_image" >"$run_dir/postgres.log" 2>&1
deadline=$((SECONDS + 30))
until timeout -k 1 3 sudo docker exec "$container" pg_isready -h 127.0.0.1 -U postgres -d todos >/dev/null; do
  if (( SECONDS >= deadline )); then echo 'PostgreSQL failed readiness' >&2; exit 1; fi
  sleep 0.25
done

wasmer=("$WASMER_BIN" run --cranelift --offline --include-webc "$REGISTRY_DIR"
  --env "DB_HOST=$db_host" --env "DB_PORT=$DB_PORT" --env DB_NAME=todos
  --env DB_USERNAME=postgres --env DB_PASSWORD=postgres --env DB_SSL=false)
sql() {
  timeout -k 1 5 sudo docker exec "$container" psql -XAt -v ON_ERROR_STOP=1 -U postgres -d todos -c "$1"
}

"${wasmer[@]}" "${serve_network[@]}" "${listen[@]}" --entrypoint start "$package" >"$run_dir/server.log" 2>&1 &
server_pid=$!
origin="http://127.0.0.1:$PORT"
body="$run_dir/body"
headers="$run_dir/headers"
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null &&
     jq -e '. == {database:"postgresql",configured:true}' "$body" >/dev/null; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'PostgreSQL fixture failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done
echo 'PASS ready with database configuration'

request() {
  local expected=$1 path=$2 status
  shift 2
  status=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -D "$headers" \
    -w '%{http_code} %{content_type}' "$@" "$origin$path")
  [[ $status == "$expected application/json; charset=utf-8" ]]
  tr -d '\r' <"$headers" | grep -ixq 'cache-control: no-store'
}

request 201 /items -H 'Content-Type: application/json' --data '{"name":"Original"}'
id=$(jq -er 'select(.name == "Original") | .id' "$body")
[[ $id =~ ^[1-9][0-9]*$ ]]
[[ $(sql "SELECT name FROM items WHERE id = $id") == Original ]]
echo 'PASS create writes a row'

request 200 "/items/$id"
jq -e --argjson id "$id" '. == {id:$id,name:"Original"}' "$body" >/dev/null
echo 'PASS read returns the saved row'

request 200 "/items/$id" -X PATCH -H 'Content-Type: application/json' --data '{"name":"Updated"}'
jq -e --argjson id "$id" '. == {id:$id,name:"Updated"}' "$body" >/dev/null
[[ $(sql "SELECT name FROM items WHERE id = $id") == Updated ]]
echo 'PASS update changes the stored row'

request 200 "/items/$id" -X DELETE
jq -e --argjson id "$id" '. == {id:$id,name:"Updated"}' "$body" >/dev/null
[[ $(sql 'SELECT count(*) FROM items') == 0 ]]
request 404 "/items/$id"
jq -e '.error == "Item not found"' "$body" >/dev/null
request 404 /missing
jq -e '.error == "Route not found"' "$body" >/dev/null
echo 'PASS delete removes the row and missing routes return JSON 404'
