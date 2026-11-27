# Scheduled jobs on embedded Edge.js

Codex adapted the layout and dependency lock of the [pinned Hono starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-hono).
The source archive SHA-256 is
`74705648a797d7018d2310a7de404011e83e297dcb05af18b68655cb3958ff73`.
The Hono process runs a 200 ms interval and writes one record per tick to a
host-mounted file. The local test checks tick order, timestamp spacing,
the shutdown receipt, the final file record, and clean process exit.

Build with Node 26.13.1, npm 11.20.0, Anybuild 0.33.3 and Wasmer.
The test needs curl, jq, Python 3 and the offline registry in `registry.sha256`.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASIX_LANE=v2 WASMER_BIN=/path/to/wasmer-v2 REGISTRY_DIR=/path/to/registry ./test.sh
```
