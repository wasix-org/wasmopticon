# ChatGPT MCP starter suite

Codex prepared this fixture from the public [Wasmer examples MCP starter](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-mcp-chatgpt-starter).
Its source is pinned to commit `993bf9a55d3da307c5f2ecf4f4d716c63f44b764`,
with source archive SHA-256
`5f675f1eaee893c9e58466329ab790c1a59a827cd3c57036e4a49be54a81f11a`.
The app reads its bundled sample cupcake orders and runs on loopback.

The build uses Anybuild 0.33.3, uvx 0.13.9, and hash-pinned wheels for
CPython 3.13 on WASIX. The lock retains MCP 2.3.0 and uses versions of
Pydantic, CFFI, cryptography, and rpds-py available for WASIX. The
shared build normalizes the package timestamps and volume paths.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18114 ./test.sh
```

The test initializes a Streamable HTTP MCP client, lists the two tools,
then calls search and fetch against known samples. It verifies that the
returned citation resolves to the same record and that an unknown
citation returns 404.
