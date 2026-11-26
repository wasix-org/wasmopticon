# node-http-edgejs

Fixture adaptations by Codex. The [Wasmer starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-node)
provides the original package manifest and greeting. The pinned source archive
has SHA-256 `74705648a797d7018d2310a7de404011e83e297dcb05af18b68655cb3958ff73`.
Anybuild maps the guest Node command to embedded QuickJS Edge.js 0.2.5.

Build with Node 26.13.1, npm 11.20.0, Anybuild 0.33.3 and Wasmer on PATH.
Set `REGISTRY_DIR` to the local WebC registry listed in `registry.sha256`.
The test uses curl, Python 3 and jq.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer \
  WASIX_LANE=v2 PORT=18330 ./test.sh
```

Use the released Wasmer with `WASIX_LANE=v1` for the comparison. Both lanes
use the same `.anybuild/suite/package.webc`.
