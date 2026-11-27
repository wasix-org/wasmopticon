# TanStack Start on embedded Edge.js

Fixture adaptations by Codex. The pinned starter supplies the greeting and
dependency ranges. The fixture renders TanStack Start routes and submits a form
to its compiled server function. [Upstream starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-tanstack-start)

The pinned source archive SHA-256 is
`74705648a797d7018d2310a7de404011e83e297dcb05af18b68655cb3958ff73`.
Build with Node 26.13.1, npm 11.20.0, Anybuild 0.33.3 and Wasmer on PATH.
Prepare the local WebC registry using `registry.sha256`.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer \
  WASIX_LANE=v2 PORT=18384 ./test.sh
```

Use the released Wasmer with `WASIX_LANE=v1` to test the same
`.anybuild/suite/package.webc` on v1. The test covers request-time markup,
the emitted client script, the server-function POST and method check, and
the rendered 404.
