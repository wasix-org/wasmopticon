#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export PORT="${PORT:-18385}"
mkdir -p .anybuild/suite
run_dir=$(mktemp -d "$PWD/.anybuild/suite/functional.${WASIX_LANE:-unknown}.XXXXXX")
export WASMER_DIR="$run_dir/state"
export WASMER_CACHE_DIR="${WASMER_CACHE_DIR:-$run_dir/cache}"
echo "Functional evidence: $run_dir"

python3 - "$PORT" <<'PY'
import socket
import sys

with socket.socket() as listener:
    listener.bind(("127.0.0.1", int(sys.argv[1])))
PY

./serve.sh >"$run_dir/server.log" 2>&1 &
server_pid=$!
cleanup() {
  local status=$?
  trap - EXIT
  if kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    for ((attempt = 0; attempt < 30; attempt++)); do
      if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    kill -KILL "$server_pid" 2>/dev/null || true
  fi
  wait "$server_pid" 2>/dev/null || true
  if (( status != 0 )); then cat "$run_dir/server.log" >&2; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

origin="http://127.0.0.1:$PORT"
body="$run_dir/body"
marker='Hello from SolidStart on Wasmer Edge'
started=$SECONDS
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null &&
     grep -Fq "$marker" "$body"; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'SolidStart failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done
echo "PASS SolidStart SSR readiness ($((SECONDS - started))s)"


assert_output() {
  local id=$1 value=$2
  grep -Eq "<output[^>]*id=\"$id\"[^>]*>(<!--[^>]*>)*$value(<!--[^>]*>)*</output>" "$body"
}

for probe in first-request second-request; do
  result=$(curl --noproxy '*' -fsS --max-time 5 -o "$body" -w '%{content_type}' "$origin/?probe=$probe")
  [[ $result == text/html* ]]
  assert_output probe "$probe"
done
echo 'PASS request-specific SolidStart SSR'

action_path=$(python3 - "$body" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys
from urllib.parse import urlsplit

class FormParser(HTMLParser):
    action_path = None

    def handle_starttag(self, tag, attrs):
        fields = dict(attrs)
        if tag == "form" and fields.get("id") == "fixture-form":
            self.action_path = fields.get("action")

parser = FormParser()
parser.feed(Path(sys.argv[1]).read_text())
action = parser.action_path
if not action or urlsplit(action).path != "/_server":
    sys.exit(f"Expected a generated local SolidStart server function URL, got {action!r}")
if urlsplit(action).netloc or urlsplit(action).scheme:
    sys.exit("Expected a relative form action")
print(action)
PY
)
headers="$run_dir/headers"
result=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -D "$headers" -w '%{http_code}' \
  -H "Origin: $origin" --data-urlencode 'message=Edge.Js Action' "$origin$action_path")
[[ $result == 303 ]]
receipt_path='/?receipt=Edge.Js%20Action'
location=$(tr -d '\r' <"$headers" | awk 'tolower($1) == "location:" { print $2 }')
[[ $location == "$receipt_path" || $location == "$origin$receipt_path" ]]
curl --noproxy '*' -fsS --max-time 5 -o "$body" "$origin$receipt_path"
assert_output receipt 'Edge\.Js Action'
echo 'PASS rendered form invokes the server action and SSR shows its receipt'

result=$(curl --noproxy '*' -fsS --max-time 5 -o "$body" -D "$headers" -w '%{content_type}' "$origin/api/status")
[[ $result == application/json* ]]
jq -e '. == {framework: "solidstart"}' "$body" >/dev/null
tr -d '\r' <"$headers" | grep -iq '^x-fixture: solidstart$'
echo 'PASS SolidStart JSON route and response header'

result=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -w '%{http_code}' "$origin/missing")
[[ $result == 404 ]]
grep -Fq 'SolidStart route not found' "$body"
echo 'PASS rendered SolidStart 404'
