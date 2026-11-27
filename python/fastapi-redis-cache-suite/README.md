# FastAPI Redis cache fixture

Codex authored this workload using the FastAPI HTTP fixture's build
and serve setup at `38a3b20383ed30bc8660c2056df53482afb56393`. The guest
uses redis-py 5.2.1 over TCP. The test verifies a cache miss, two writes
and reads, expiry of one key, and survival of the other.

Build with Anybuild 0.33.3 and uvx 0.13.9. Testing uses a disposable
Redis 7.4 Alpine container on loopback. The image is pinned by digest,
and Docker removes the container after each run.

```sh
sudo docker pull docker.io/library/redis@sha256:7f7d30b7fdd09467bac58198a1f166dd69789d348d4fe859cccb20e0cf287fbe
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18143 DB_PORT=18163 ./test.sh
```
