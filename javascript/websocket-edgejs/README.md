# WebSocket echo on Edge.js

Codex adapted the Node HTTP starter to serve a local WebSocket echo endpoint
at `/ws`. The starter archive at commit
`1da21d1232ce101832921e4d5c8d0a81adc6b98b` has SHA-256
`74705648a797d7018d2310a7de404011e83e297dcb05af18b68655cb3958ff73`.
The fixture pins ws 8.23.0 with its npm integrity hash.
[Wasmer starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-node)
[ws 8.23.0](https://github.com/websockets/ws/releases/tag/8.23.0)

Build with Node 26.13.1, npm 11.20.0, Anybuild 0.33.3 and Wasmer on PATH.
Point `REGISTRY_DIR` at the local WebC registry listed in `registry.sha256`.
The functional test uses the built-in WebSocket client in host Node, curl
and Python 3. It compares text and binary frames, checks the server's close
code and reason, and keeps ten connections open for a parallel echo round trip.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer \
  WASIX_LANE=v2 PORT=18387 ./test.sh
```

Use the released CLI with `WASIX_LANE=v1` for comparison against the same
`.anybuild/suite/package.webc`.
