# Worker threads on embedded Edge.js

Codex authored this fixture. It starts a Node `Worker` and waits for it to
count and sum the primes up to 100,000. The parent verifies the result,
the worker thread ID, isolation of the worker's global state and
`workerData`, and a clean worker exit. The test runs offline as a CLI
command and uses no port.

Build with Node 26.13.1, npm 11.20.0, Anybuild 0.33.3 and Wasmer on PATH.
Prepare the local QuickJS Edge.js registry listed in `registry.sha256`.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer ./test.sh
```

Use the same `.anybuild/suite/package.webc` with released Wasmer and a
C API-enabled WASIX v2 build.
