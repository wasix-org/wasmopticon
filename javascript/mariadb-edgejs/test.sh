#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${WASMER_BIN:=wasmer}"
: "${REGISTRY_DIR:?Set REGISTRY_DIR to the local WebC registry root}"
: "${WASIX_LANE:?Set WASIX_LANE to v1 or v2}"
: "${PORT:=18392}"
: "${DB_PORT:=18393}"

mariadb_image=docker.io/library/mariadb@sha256:5e73baf8179b29f115101bb102763a47a017361f3e9792daccba6646c3ab1532
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
    app.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    database.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    app.bind(("127.0.0.1", int(sys.argv[1])))
    database.bind(("127.0.0.1", int(sys.argv[2])))
PY

container="wasmopticon-node-mariadb-${run_dir##*.}"
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
    for log in mariadb server; do
      if [[ -f "$run_dir/$log.log" ]]; then cat "$run_dir/$log.log" >&2; fi
    done
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

timeout -k 2 20 sudo docker run --rm --pull=never -d --name "$container" \
  -e MARIADB_DATABASE=fixture -e MARIADB_USER=fixture \
  -e MARIADB_PASSWORD=fixture-password -e MARIADB_RANDOM_ROOT_PASSWORD=1 \
  -p "127.0.0.1:$DB_PORT:3306" "$mariadb_image" >"$run_dir/mariadb.log" 2>&1
sql() {
  timeout -k 1 5 sudo docker exec -e MYSQL_PWD=fixture-password "$container" \
    mariadb --protocol=TCP --skip-ssl -h 127.0.0.1 -u fixture -D fixture --batch --skip-column-names -e "$1"
}

deadline=$((SECONDS + 35))
until [[ $(sql 'SELECT 1' 2>/dev/null) == 1 ]]; do
  if (( SECONDS >= deadline )); then echo 'MariaDB failed readiness' >&2; exit 1; fi
  sleep 0.25
done

wasmer=("$WASMER_BIN" run --cranelift --offline --include-webc "$REGISTRY_DIR"
  --env "DB_HOST=$db_host" --env "DB_PORT=$DB_PORT" --env DB_NAME=fixture
  --env DB_USERNAME=fixture --env DB_PASSWORD=fixture-password)
"${wasmer[@]}" "${serve_network[@]}" "${listen[@]}" --entrypoint start "$package" >"$run_dir/server.log" 2>&1 &
server_pid=$!
origin="http://127.0.0.1:$PORT"
body="$run_dir/body"
headers="$run_dir/headers"
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null &&
     jq -e '.database == "mariadb" and (.version | contains("MariaDB"))' "$body" >/dev/null; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'MariaDB fixture failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done
echo 'PASS pooled query reached MariaDB'

request() {
  local expected=$1 path=$2 status
  shift 2
  status=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -D "$headers" \
    -w '%{http_code} %{content_type}' "$@" "$origin$path")
  [[ $status == "$expected application/json; charset=utf-8" ]]
  tr -d '\r' <"$headers" | grep -ixq 'cache-control: no-store'
}

request 200 /entries
jq -e '. == []' "$body" >/dev/null

name="O'Reilly via prepared statement"
payload=$(jq -nc --arg name "$name" '{name:$name,commit:true}')
request 201 /entries -H 'Content-Type: application/json' --data "$payload"
id=$(jq -er --arg name "$name" 'select(.committed and .entry.name == $name) | .entry.id' "$body")
[[ $id =~ ^[1-9][0-9]*$ ]]
[[ $(sql "SELECT name FROM entries WHERE id = $id") == "$name" ]]
echo 'PASS prepared statement committed the quoted name exactly'

request 200 /entries -H 'Content-Type: application/json' --data '{"name":"rolled back","commit":false}'
rolled_back_id=$(jq -er 'select(.committed == false and .entry.name == "rolled back") | .entry.id' "$body")
[[ $rolled_back_id =~ ^[1-9][0-9]*$ && $rolled_back_id != "$id" ]]
[[ $(sql "SELECT COUNT(*) FROM entries WHERE id = $rolled_back_id") == 0 ]]
echo 'PASS transaction saw its own insert and rollback removed it from MariaDB'
prepared_status=$(sql "SHOW GLOBAL STATUS LIKE 'Com_stmt_execute'")
read -r counter executions <<<"$prepared_status"
[[ $counter == Com_stmt_execute && $executions =~ ^[0-9]+$ ]]
(( executions >= 4 ))
echo "PASS MariaDB recorded $executions prepared statement executions"

request 200 /entries
jq -e --argjson id "$id" --arg name "$name" '. == [{id:$id,name:$name}]' "$body" >/dev/null
request 400 /entries -H 'Content-Type: application/json' --data '{"name":"missing commit flag"}'
jq -e '.error == "Name and commit flag are required"' "$body" >/dev/null
request 404 /missing
jq -e '.error == "Route not found"' "$body" >/dev/null
echo 'PASS pooled read returned only the committed row, with JSON 400 and 404 checks'
