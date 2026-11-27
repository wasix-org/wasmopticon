# PHP starter suite

Fixture authored by Codex. `app/index.php` and `app/info.php` are the
`php-starter` template from
[wasmer-examples/php-wasmer-starter](https://github.com/wasmer-examples/php-wasmer-starter/tree/67a46ad74e66c4aced0ef62fe866c7f39f63d8eb)
at `67a46ad74e66c4aced0ef62fe866c7f39f63d8eb`. The source tarball had
SHA-256 `cb8af474b37c09ae0fe37f140f17dba6bf54ba6112532190d7fa408a406485a5`.
The fixture adds an OPcache statistics endpoint and uses the PHPix 8.4
32-bit packages pinned by the sibling PHPix starter.

Use Anybuild 0.33.3. The tests bind only to loopback and use the same WebC
from `.anybuild/suite/package.webc` on both runtimes.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 PORT=18200 ./test.sh
WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 PORT=18200 ./test.sh
```

The suite checks the greeting, generated number, PHP info and 404.
It records WebC mtime and OPcache hit/miss deltas over 20 warm requests
with timestamp validation enabled and revalidation every request. Results
are in `.anybuild/suite/runs/`.
