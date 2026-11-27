# FastAPI WebSocket echo

The app is the template from snapshot
`python/fastapi_websockets/324f6e1b41b73e5ed94163b0d210cec3f83264e6`.
Uvicorn 0.35.0 uses the pinned pure-Python websockets 15.0.1 wheel.
The guest dependency lock also includes the snapshot's pydantic-core WASIX
wheel. The local client checks the page without loading external assets.

```sh
ANYBUILD_BIN=/path/to/anybuild WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=38382 ./test.sh
```

Use Anybuild 0.33.3, uvx 0.13.9, and Node 22.18 or later. The test checks the upgrade at
`/api/ws`, text echoes including a Unicode JSON string, clean close, and
reconnection. For the Artillery 2.0.34 scenario, run
`PORT=38382 WASMER_BIN=/path/to/wasmer ./serve.sh` in a dedicated process.
The scenario checks two matching echoes per connection.
