# Python HTTP server starter

Codex authored this fixture around the standard-library HTTP server from
[wasmer-examples/python-wasmer-starter](https://github.com/wasmer-examples/python-wasmer-starter/tree/307b1736faa847ae32620db17924a1c8ea3118c6)
at `307b1736faa847ae32620db17924a1c8ea3118c6`. The GitHub source archive
SHA-256 is `88234f0d5012087c0ea03beabc9eb45a410a749e6ce53b459c2fc4c5987a7ad5`.

The test checks the JSON greeting on multiple paths, HEAD on a missing
file, and POST method rejection. The fixture has zero wheel dependencies.

```sh
# Anybuild 0.33.3 and uvx 0.13.9 on PATH.
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18103 ./test.sh
```
