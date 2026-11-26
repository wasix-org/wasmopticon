# Django starter

Codex authored this fixture around the Django starter from
[wasmer-examples/django-wasmer-starter](https://github.com/wasmer-examples/django-wasmer-starter/tree/b6e835b5a7288d37981fbc04b8e3590f14cefdd7)
at `b6e835b5a7288d37981fbc04b8e3590f14cefdd7`. The GitHub source archive SHA-256 is
`33f7d98b817e9fa01bf850814cd40910596c2ce4e6d0362f45b16fd5ab8eae34`.

The fixture runs the starter's WSGI app with its SQLite profile and
WhiteNoise static middleware. Startup migrates a fresh guest database and
creates a fixture-only admin. The test rejects a login without a CSRF
token, logs in with a valid token, writes and reads an admin group, and
checks the starter text asset, admin CSS, and a 404.

Build with Anybuild 0.33.3 and uvx 0.13.9 on PATH. The WASIX wheel lock uses
the starter's pinned Django and WhiteNoise versions.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18100 ./test.sh
```
