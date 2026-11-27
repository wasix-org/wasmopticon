# Outbound fetch on embedded Edge.js

Codex adapted the basic Node HTTP layout from the [pinned Node starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-node).
The source archive SHA-256 is
`74705648a797d7018d2310a7de404011e83e297dcb05af18b68655cb3958ff73`.
The fixture uses built-in `fetch` to reach a host loopback upstream.
Its test verifies JSON and header propagation, an upstream 404, and
cancellation after the upstream receives a slow request.

Build with Node 26.13.1, npm 11.20.0, Anybuild 0.33.3 and Wasmer.
The test needs curl, jq, Python 3 and the offline registry in `registry.sha256`.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASIX_LANE=v2 WASMER_BIN=/path/to/wasmer-v2 REGISTRY_DIR=/path/to/registry ./test.sh
```

v1 runs with `--net` and connects to the upstream at `127.0.0.1`.
v2 runs with `--net --publish 127.0.0.1:$PORT:8080` and connects through
the guest gateway at `10.0.2.2`. The upstream binds only to host loopback
in both lanes. Set `UPSTREAM_PORT` to override its OS-assigned port.
