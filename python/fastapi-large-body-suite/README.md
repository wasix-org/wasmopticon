# FastAPI large body fixture

Codex authored this workload using the build and serve setup from the
FastAPI HTTP fixture at `147cc458bbac6ae0de166bb0a24fa37a46700d60`.
It uses the same hash-locked Python 3.13 dependencies.

The client sends 20 MiB of deterministic binary data to
`POST /round-trip`. The server hashes request chunks as they arrive and
returns a buffered binary response with the digest. The client verifies every
downloaded byte, the total length, and an independently computed
SHA-256.

Build with Anybuild 0.33.3 and uvx 0.13.9.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18132 ./test.sh
```
