# Node.js PostgreSQL on embedded Edge.js

Codex adapted the [PostgreSQL starter](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/js-postgresql).
It retains the configuration status route and adds SQL-backed JSON CRUD
using the pure JavaScript `pg` driver. The pinned source archive SHA-256 is
`5f675f1eaee893c9e58466329ab790c1a59a827cd3c57036e4a49be54a81f11a`.

Build with Node 26.13.1, npm 11.20.0 and Anybuild 0.33.3. Set `REGISTRY_DIR`
to the local WebC registry listed in `registry.sha256`. The test uses
`sudo docker`, curl, jq and Python 3.

```sh
sudo docker pull docker.io/library/postgres@sha256:58b1ad1807d86ca43d0e37fded9f0a899a7ab8763fa9576a63059a52de223e1b
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASIX_LANE=v2 WASMER_BIN=/path/to/wasmer-v2 REGISTRY_DIR=/path/to/registry ./test.sh
```
