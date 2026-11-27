# Laravel on MariaDB

Authored by Codex. Uses the same pinned Laravel Blade starter, Composer
lock and PHPix 8.4 runtime as the sibling Laravel SQLite fixture. The
build verifies the example archive and installs from the upstream lock.

The test runs the digest-pinned MariaDB image with `sudo docker`,
waits for InnoDB, and applies the template migrations using the guest
PHP CLI. It writes and reads a row over HTTP, inserts a second row in a
transaction that intentionally throws, and verifies the first row
remains while the second is absent. A MariaDB query confirms the final
table contents. The temporary container is removed on exit.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 ./test.sh
WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 ./test.sh
```

The default loopback ports are 18250 for HTTP and 18254 for MariaDB.
Override them with `PORT` and `MARIADB_PORT`.
