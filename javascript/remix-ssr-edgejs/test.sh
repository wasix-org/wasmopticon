#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export PORT="${PORT:-18380}"
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
greeting='Hello from Remix on Wasmer Edge'
started=$SECONDS
deadline=$((SECONDS + 45))
while :; do
  if curl --noproxy '*' -fsS --max-time 2 "$origin/" -o "$body" 2>/dev/null &&
     grep -Fq -- "$greeting" "$body"; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo 'remix-ssr-edgejs failed readiness' >&2
    exit 1
  fi
  sleep 0.25
done
echo "PASS greeting and readiness ($((SECONDS - started))s)"

headers="$run_dir/headers"

request() {
  local path=$1 expected_status=$2 expected_type=$3 result
  shift 3
  result=$(curl --noproxy '*' -sS --max-time 5 -o "$body" -D "$headers" \
    -w '%{http_code} %{content_type}' "$@" "$origin$path")
  [[ $result == "$expected_status $expected_type"* ]]
  tr -d '\r' <"$headers" | grep -ixq 'x-fixture: js-remix-ssr'
}

request '/?name=first' 200 text/html
grep -Fq '<output id="loader-value">first</output>' "$body"
form_action=$(python3 - "$body" <<'PYTHON'
from html.parser import HTMLParser
from pathlib import Path
import sys


class FormParser(HTMLParser):
    action = None

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "form" and attributes.get("method", "").lower() == "post":
            self.action = attributes.get("action")


parser = FormParser()
parser.feed(Path(sys.argv[1]).read_text())
if parser.action is None or not parser.action.startswith("/") or parser.action.startswith("//"):
    sys.exit("Expected a local POST form action")
print(parser.action)
PYTHON
)
request '/?name=second' 200 text/html
grep -Fq '<output id="loader-value">second</output>' "$body"
echo 'PASS SSR renders distinct route-loader markup and a form'

request "$form_action" 200 text/html --data-urlencode 'message=paired action <verified>'
grep -Fq '<output id="action-value">paired action &lt;verified&gt;</output>' "$body"
echo 'PASS form action renders the submitted, escaped value'

request '/json?value=route-data' 200 application/json -H 'X-Probe: local-probe'
jq -e '. == {value: "route-data", probe: "local-probe"}' "$body" >/dev/null
echo 'PASS JSON route returns query data and the request header'

request '/missing' 404 text/html
grep -Fq '<h1>Not Found</h1>' "$body"
echo 'PASS framework missing route returns a 404 document'
