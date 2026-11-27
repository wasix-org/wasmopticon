# Node.js MariaDB on embedded Edge.js

Codex adapted the Node HTTP starter to connect to a local MariaDB using
a mysql2 pool at version 3.24.6. The source archive at commit
`1da21d1232ce101832921e4d5c8d0a81adc6b98b` has SHA-256
`74705648a797d7018d2310a7de404011e83e297dcb05af18b68655cb3958ff73`.
[Wasmer starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-node)
[mysql2 3.24.6](https://github.com/sidorares/node-mysql2/releases/tag/v3.24.6)

Build with Node 26.13.1, npm 11.20.0 and Anybuild 0.33.3. Set `REGISTRY_DIR`
to the local WebC registry listed in `registry.sha256`. The test uses
`sudo docker`, curl, jq and Python 3. It starts a fresh MariaDB fixture
on host loopback, checks a committed prepared statement and a rolled-back
transaction against the database, then verifies the pooled HTTP read.

```sh
sudo docker pull docker.io/library/mariadb@sha256:5e73baf8179b29f115101bb102763a47a017361f3e9792daccba6646c3ab1532
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
REGISTRY_DIR=/path/to/registry WASIX_LANE=v2 WASMER_BIN=/path/to/wasmer-v2 \
  PORT=18392 DB_PORT=18393 ./test.sh
```

Use `WASIX_LANE=v1` and the released CLI for comparison against the same
`.anybuild/suite/package.webc`.
