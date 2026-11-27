# FastAPI scheduled jobs

Codex added this interval-job workload using the build and launch setup
from `python/fastapi-http-suite` in wasmopticon at `e6bf6e1`. FastAPI's
lifespan starts a guest Python thread that records a SQLite row each
second. The host test checks the rows and spacing, requests shutdown
over loopback, and verifies a joined-worker marker and a stable row
count in the mounted database after the listener closes.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18142 ./test.sh
```

Build with Anybuild 0.33.3 and uvx 0.13.9.
