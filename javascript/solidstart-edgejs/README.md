# SolidStart on Edge.js

Codex adapted the pinned starter for the local wasmopticon suite.
The fixture keeps the upstream greeting and replaces its plain HTTP handler
with SolidStart SSR, a router action compiled as a server function, and an
API route. The test checks per-request markup, the actual generated form
action, its redirect and rendered receipt, a JSON route, and the 404 page.
[Upstream starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-solidstart)

Build with Node 26.13.1, npm 11.20.0, and Anybuild 0.33.3. The local
registry must contain the WebCs pinned in `registry.sha256`.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
REGISTRY_DIR=/path/to/registry WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 PORT=18385 ./test.sh
REGISTRY_DIR=/path/to/registry WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 PORT=18385 ./test.sh
```
