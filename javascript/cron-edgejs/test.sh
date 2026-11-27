#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${WASMER_BIN:=wasmer}"
: "${REGISTRY_DIR:?Set REGISTRY_DIR to the local WebC registry root}"
: "${WASIX_LANE:?Set WASIX_LANE to v1 or v2}"
: "${PORT:=18396}"

registry_checksums="$PWD/registry.sha256"
(cd "$REGISTRY_DIR" && sha256sum --strict --quiet -c "$registry_checksums")
mkdir -p .anybuild/suite
run_dir=$(mktemp -d "$PWD/.anybuild/suite/functional.$WASIX_LANE.XXXXXX")
mkdir "$run_dir/ticks"
export WASMER_DIR="$run_dir/state"
export WASMER_CACHE_DIR="${WASMER_CACHE_DIR:-$run_dir/cache}"
echo "Functional evidence: $run_dir"

case "$WASIX_LANE" in
  v1) network=(--net --env HOST=127.0.0.1 --env "PORT=$PORT");;
  v2) network=(--publish "127.0.0.1:$PORT:8080" --env HOST=0.0.0.0 --env PORT=8080);;
  *) echo "Unknown WASIX_LANE: $WASIX_LANE" >&2; exit 2;;
esac

"$WASMER_BIN" run --cranelift --offline --include-webc "$REGISTRY_DIR" \
  "${network[@]}" --volume "$run_dir/ticks:/state" --entrypoint start \
  .anybuild/suite/package.webc >"$run_dir/server.log" 2>&1 &
server_pid=$!
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n $server_pid ]]; then
    if kill -TERM "$server_pid" 2>/dev/null; then
      for ((attempt=0; attempt<30; attempt++)); do
        kill -0 "$server_pid" 2>/dev/null || break
        sleep 0.1
      done
      kill -KILL "$server_pid" 2>/dev/null || true
    fi
    wait "$server_pid" 2>/dev/null || true
  fi
  if (( status != 0 )); then cat "$run_dir/server.log" >&2; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

origin="http://127.0.0.1:$PORT"
body="$run_dir/body"
ticks="$run_dir/ticks/ticks.jsonl"
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null &&
     jq -e '. == {fixture:"cron-edgejs",intervalMs:200}' "$body" >/dev/null; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'Cron server failed readiness' >&2
    exit 1
  fi
  sleep 0.1
done

deadline=$((SECONDS + 10))
while [[ $(wc -l <"$ticks") -lt 5 ]]; do
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'Fewer than four scheduled ticks reached the mounted file' >&2
    exit 1
  fi
  sleep 0.1
done

curl --noproxy '*' -fsS --max-time 5 -X POST "$origin/shutdown" -o "$body"
deadline=$((SECONDS + 10))
while kill -0 "$server_pid" 2>/dev/null; do
  if (( SECONDS >= deadline )); then echo 'Cron server did not exit' >&2; exit 1; fi
  sleep 0.1
done
wait "$server_pid"
server_pid=

python3 - "$ticks" "$body" <<'PY'
import json
import sys
from pathlib import Path

records = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
receipt = json.loads(Path(sys.argv[2]).read_text())
ticks = records[1:-1]
assert len(ticks) >= 4, records
assert records[0]["event"] == "start" and records[0]["count"] == 0, records
assert records[-1]["event"] == "stop" and records[-1]["count"] == len(ticks), records
assert receipt == {"stopped": True, "count": len(ticks)}, receipt
assert [(row["event"], row["count"]) for row in ticks] == [
    ("tick", i) for i in range(1, len(ticks) + 1)
], records
gaps = [end["ms"] - start["ms"] for start, end in zip(records, ticks)]
assert all(140 <= gap <= 2000 for gap in gaps), gaps
print(f"PASS {len(ticks)} persisted ticks with 200 ms interval, observed gaps {gaps}")
PY
if curl --noproxy '*' -sS --max-time 2 "$origin/" >/dev/null 2>&1; then
  echo 'Cron listener still reachable after shutdown' >&2
  exit 1
fi
echo 'PASS shutdown response, last persisted stop marker and clean process exit'
