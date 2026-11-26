# Remix on embedded Edge.js

Fixture adaptations by Codex. The pinned starter supplies the greeting and
dependency versions. The fixture replaces its bare Node greeting with
Remix route loaders, server rendering, and a form action.
[Upstream starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-remix-ssr)

The pinned source archive SHA-256 is
`74705648a797d7018d2310a7de404011e83e297dcb05af18b68655cb3958ff73`.
Build with Node 26.13.1, npm 11.20.0, Anybuild 0.33.3 and Wasmer on PATH.
The runtime dependencies are listed in `registry.sha256`.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer \
  WASIX_LANE=v2 PORT=18380 ./test.sh
```

Use released Wasmer with `WASIX_LANE=v1` to test the same
`.anybuild/suite/package.webc` on v1.
