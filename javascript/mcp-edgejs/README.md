# MCP on embedded Edge.js

Codex adapted the [MCP starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-mcp).
The pinned source archive SHA-256 is
`74705648a797d7018d2310a7de404011e83e297dcb05af18b68655cb3958ff73`.
This fixture exercises the upstream stateless MCP server and greeting tool
over local HTTP. The SDK sends JSON responses so the harness can assert the
initialize handshake, tool listing and an actual tool call.

Build with Node 26.13.1, npm 11.20.0 and Anybuild 0.33.3. Set `REGISTRY_DIR`
to the local WebC registry listed in `registry.sha256`.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASIX_LANE=v2 WASMER_BIN=/path/to/wasmer-v2 REGISTRY_DIR=/path/to/registry ./test.sh
```
