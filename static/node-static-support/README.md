# Node static fixture support

Authored by Codex. Each fixture's `inputs.env` pins its template revision,
source archive checksum, build output directory and HTTP checks. Anybuild
0.33.3 runs `npm ci` and the template's build under host Node 26.13.1 and
npm 11.20.0. The build copies only the exported site into the WebC, along
with the Wasm from the pinned static-web-server 2.44.0 package.

From a fixture directory, run `WASMER_BIN=/path/to/wasmer ./build.sh` and
then `WASMER_BIN=/path/to/wasmer PORT=<loopback-port> ./test.sh`. Use the
same WebC for both runtime lanes. `test.sh` detects loopback port
publication support from the runtime CLI. Each fixture uses its own
default port and saves evidence under `.anybuild/suite/`.
