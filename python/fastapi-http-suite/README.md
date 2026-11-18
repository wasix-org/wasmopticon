# FastAPI HTTP starter

The app is the FastAPI template from snapshot
`python/fastapi/3a8d2560622bf096970b4d10d6a193c02ef72bbd`.
Uvicorn 0.35.0 uses asyncio and h11. The guest dependency lock keeps the
snapshot's versions for this Uvicorn profile, including the CPython 3.13
WASIX wheel for pydantic-core. Anybuild 0.33.3 selects
`python/python@=3.13.20`.

```sh
ANYBUILD_BIN=/path/to/anybuild WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=38381 ./test.sh
```

The first build fetches verified dependencies. Subsequent launches resolve
WebCs from the offline registry staged by the build. The test chooses a free
loopback port when `PORT` is unset and tests greeting JSON, the OpenAPI
schema, and the expected 404. For the Artillery 2.0.34 scenario, run
`PORT=38381 WASMER_BIN=/path/to/wasmer ./serve.sh` in a dedicated process.
