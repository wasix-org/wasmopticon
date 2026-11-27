# Astro SSR on Edge.js

Codex adapted the pinned starter for the local wasmopticon suite.
The test checks request-specific HTML, a form submission and JSON response, a response header, and a 404.
[Upstream starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-astro-ssr)

Build with Node 26.13.1, npm 11.20.0, and Anybuild 0.33.3. The local
registry must contain the WebCs pinned in `registry.sha256`.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
REGISTRY_DIR=/path/to/registry WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 PORT=18381 ./test.sh
REGISTRY_DIR=/path/to/registry WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 PORT=18381 ./test.sh
```
