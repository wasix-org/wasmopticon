# PHPix I/O suite

Authored by Codex. This package uses the PHPix 8.4 32-bit runtime pinned
by the sibling PHPix starter. Its three test modes run locally.

| Mode | Coverage | Default HTTP port |
| --- | --- | --- |
| `upload` | A 20 MiB multipart upload, exact download and SHA-256 checks, plus rejection at 20 MiB + 1 | 18251 |
| `session` | 20 parallel session writes on four workers, then 20 independent reads | 18252 |
| `outbound` | cURL and PHP stream HTTP success and TCP connect timeout | 18253 |

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 ./test.sh upload
WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 ./test.sh upload
```

The suite runner uses the `upload`, `session`, and `outbound-curl`
profiles via `PHPIX_IO_MODE` and `PHPIX_IO_CLIENT`. Positional arguments
take precedence. Use `./test.sh outbound curl` for a direct cURL run.

The strict `./test.sh outbound stream` check is opt-in and known to
fail on both runtimes. The blocking PHP stream ignores its 500 ms
connect budget, so the host client exits after seven seconds.

The outbound test starts
a host loopback HTTP server and separately saturates a loopback TCP
listener's backlog. Their ports default to 18255 and 18256, configurable
with `UPSTREAM_PORT` and `TIMEOUT_PORT`. The connect budget in PHP is
500 ms on both clients.
