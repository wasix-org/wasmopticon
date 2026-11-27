# Redis BullMQ worker on embedded Edge.js

Codex authored this fixture. A loopback HTTP producer sends jobs to BullMQ
using ioredis. The test polls for both results over HTTP, independently
reads the stored results from Redis, and checks the JSON 404 responses.

Build with Node 26.13.1, npm 11.20.0, Anybuild 0.33.3 and Wasmer on PATH.
Prepare the local QuickJS Edge.js registry from `registry.sha256`. Pull the
pinned official Redis image before testing. The test uses curl, Python 3, jq
and `sudo docker` and creates a disposable Redis container bound to
host loopback. Set `PORT` to override the HTTP port (default 18394) or
`REDIS_PORT` or `DB_PORT` to override the Redis port (default 18395).

```sh
sudo docker pull docker.io/library/redis@sha256:7f7d30b7fdd09467bac58198a1f166dd69789d348d4fe859cccb20e0cf287fbe
WASMER_BIN=/path/to/wasmer ./build.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer WASIX_LANE=v2 ./test.sh
```

Use released Wasmer and `WASIX_LANE=v1` to test the same WebC on v1.
