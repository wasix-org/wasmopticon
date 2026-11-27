# FastAPI SSE suite

Codex added a Server-Sent Events endpoint to the FastAPI starter in
`python/fastapi/3a8d2560622bf096970b4d10d6a193c02ef72bbd`. The fixture uses
the FastAPI HTTP suite's hash-pinned WASIX wheels.
[Upstream FastAPI starter](https://github.com/wasmer-examples/fastapi-wasmer-starter/tree/3a8d2560622bf096970b4d10d6a193c02ef72bbd)

Anybuild 0.33.3 and uvx 0.13.9 select the pinned Python 3.13.20 package
and install the dependencies for WASIX.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASMER_BIN=/path/to/wasmer-v1 PORT=18130 ./test.sh
WASMER_BIN=/path/to/wasmer-v2 PORT=18130 ./test.sh
```

FastAPI's `StreamingResponse` yields two SSE events with a two-second
pause. The test reads each event as it arrives over one HTTP connection,
verifies the event framing and headers, and requires at least one second
between arrivals to detect buffering. Both lanes run the same WebC.
