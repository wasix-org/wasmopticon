# FastAPI Redis worker suite

Codex wrote this fixture using the FastAPI HTTP suite's server adapter and
wheel lock. The producer app appends jobs to Redis. A separate thread
inside the WASIX guest waits on `BLPOP`, transforms each job, and records
results. A Redis script appends the result only on the first completion
for each job ID.

The test starts an isolated Redis 7.4 Alpine container on loopback. It
observes the worker blocking before sending jobs, then sends a duplicate
ID with a different payload and a final marker job. The results must
preserve queue order and the original payload for the duplicated ID.

```sh
sudo docker pull docker.io/library/redis@sha256:7f7d30b7fdd09467bac58198a1f166dd69789d348d4fe859cccb20e0cf287fbe
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 PORT=18141 DB_PORT=18161 ./test.sh
WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 PORT=18141 DB_PORT=18161 ./test.sh
```

The build uses Anybuild 0.33.3 and uvx 0.13.9. The dependency lock pins
redis-py 6.4.0 and the FastAPI dependencies for Python 3.13.20 on WASIX.
Both lanes use the same WebC. The harness removes its server and Redis
container on exit.
