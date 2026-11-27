#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${WASMER_BIN:=wasmer}"
: "${REGISTRY_DIR:?Set REGISTRY_DIR to the local WebC registry root}"
: "${WASIX_LANE:?Set WASIX_LANE to v1 or v2}"
: "${PORT:=18300}"
: "${DB_PORT:=18301}"

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
    migrate_network=(--net)
    serve_network=(--net)
    ;;
  v2)
    db_host=10.0.2.2
    listen=(--env HOST=0.0.0.0 --env PORT=8080)
    migrate_network=(--net)
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

container="wasmopticon-todo-${run_dir##*.}"
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
    for log in postgres migrate server; do
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

timeout -k 3 60 "${wasmer[@]}" "${migrate_network[@]}" --entrypoint migrate "$package" >"$run_dir/migrate.log" 2>&1
[[ $(sql 'SELECT count(*) FROM todos') == 0 ]]
echo 'PASS packaged migration created an empty todos table'

"${wasmer[@]}" "${serve_network[@]}" "${listen[@]}" --entrypoint start "$package" >"$run_dir/server.log" 2>&1 &
server_pid=$!
origin="http://127.0.0.1:$PORT"
body="$run_dir/body"
headers="$run_dir/headers"
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null &&
     grep -Fq 'Nothing here yet.' "$body"; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'Astro failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done
echo 'PASS Astro SSR rendered an empty list'

post() {
  local result
  result=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -D "$headers" -w '%{http_code}' \
    -H "Origin: $origin" --data "$1" "$origin/todos")
  [[ $result == 303 ]]
  tr -d '\r' <"$headers" | grep -ixq 'location: /'
}
page() {
  curl --noproxy '*' -fsS --max-time 5 "$origin/" -o "$body"
}

post 'action=create&title=Packaged+todo'
id=$(sql "SELECT id FROM todos WHERE title = 'Packaged todo' AND NOT completed")
[[ $id =~ ^[1-9][0-9]*$ ]]
page
grep -Fq 'Packaged todo' "$body"
grep -Fq '1 open' "$body"
echo 'PASS create persisted and SSR rendered the todo'

post "action=toggle&id=$id&completed=true"
[[ $(sql "SELECT completed FROM todos WHERE id = $id") == t ]]
page
grep -Eq 'class="done"[^>]*>Packaged todo' "$body"
grep -Fq '0 open' "$body"
echo 'PASS toggle persisted and SSR rendered completion'

post "action=delete&id=$id"
[[ $(sql 'SELECT count(*) FROM todos') == 0 ]]
page
grep -Fq 'Nothing here yet.' "$body"
echo 'PASS delete persisted and SSR rendered the empty list'
