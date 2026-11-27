# Nitro on Edge.js

Fixture adaptations by Codex. The fixture keeps the starter greeting and uses Nitro's node-server preset and file-based routes.
The source archive at commit `1da21d1232ce101832921e4d5c8d0a81adc6b98b` has SHA-256
`74705648a797d7018d2310a7de404011e83e297dcb05af18b68655cb3958ff73`.
[Wasmer starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-nitro)

Build with Node 26.13.1, npm 11.20.0, Anybuild 0.33.3 and Wasmer on PATH.
Set `REGISTRY_DIR` to the local WebC registry listed in `registry.sha256`.
The test checks the greeting, a JSON response, a JSON POST echo with request
and response headers, and the missing-route error. It uses curl, jq and Python 3.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer \
  WASIX_LANE=v2 PORT=18378 ./test.sh
```

Use the released CLI with `WASIX_LANE=v1` for comparison against the same
`.anybuild/suite/package.webc`.
