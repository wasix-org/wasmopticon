# FastAPI and SQLAlchemy starter

Codex authored this fixture around the todo app from
[wasmerio/examples](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-fastapi-sqlalchemy-starter)
at `993bf9a55d3da307c5f2ecf4f4d716c63f44b764`, directory
`python-fastapi-sqlalchemy-starter`. The GitHub monorepo source archive
SHA-256 is `5f675f1eaee893c9e58466329ab790c1a59a827cd3c57036e4a49be54a81f11a`.

The test creates, lists, and updates a todo, checks validation and the
HTML view, then stops the guest. It starts a fresh guest with the same
SQLite volume, verifies the saved record, deletes it, and checks the
missing-item response. Each run gets its own temporary volume.

Build with Anybuild 0.33.3 and uvx 0.13.9 on PATH. The WASIX wheel lock
selects a FastAPI and Pydantic combination compatible with the published
CPython 3.13 WASIX wheel for pydantic-core.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18102 ./test.sh
```
