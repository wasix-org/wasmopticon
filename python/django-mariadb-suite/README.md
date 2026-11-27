# Django with MariaDB

Codex authored this database fixture around the Django starter at
`b6e835b5a7288d37981fbc04b8e3590f14cefdd7`. The pinned GitHub archive
SHA-256 is `33f7d98b817e9fa01bf850814cd40910596c2ce4e6d0362f45b16fd5ab8eae34`.
[Upstream Django starter](https://github.com/wasmer-examples/django-wasmer-starter/tree/b6e835b5a7288d37981fbc04b8e3590f14cefdd7)

The fixture starts a disposable MariaDB container with a loopback-only
published port. The guest uses Django's MySQL backend with the pinned
pure-Python PyMySQL driver. It migrates the database on startup, then
exercises the built-in auth group model through HTTP. The test verifies
a committed write and readback, a rolled-back insert, and rejection of a
duplicate name. A direct query inside the container verifies the
migration record and the only surviving row.

The container uses
`docker.io/library/mariadb@sha256:5e73baf8179b29f115101bb102763a47a017361f3e9792daccba6646c3ab1532`.
Build with Anybuild 0.33.3 and uvx 0.13.9. The test uses Docker from
`PATH`, falls back to passwordless `sudo -n docker` if needed, and
accepts `DOCKER_BIN` as an explicit executable override.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18140 DB_PORT=18160 ./test.sh
```
