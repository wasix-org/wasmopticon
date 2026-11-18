# PHPix starter

This fixture retains the index from the `php/php_simple` snapshot at
`74049aef895eee58d061974e8a79616765eed2d4` and adds a POST endpoint that
round-trips request bytes through a PHP temporary file.

Use Anybuild 0.33.3 and an absolute executable path in `WASMER_BIN`.

```sh
ANYBUILD_BIN=/path/to/anybuild WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 PORT=18140 ./test.sh
WASMER_BIN=/path/to/wasmer-next WASIX_LANE=v2 PORT=18140 ./test.sh
```

The build stores the staged manifest under `.anybuild/wasmer/` and the
package at `.anybuild/suite/package.webc`. The runtime inputs are verified
against `runtime.tsv` and copied from `WEBC_SOURCE_DIR` when available, or
downloaded from the Wasmer CDN. Test runs use the local inputs offline,
with separate v1 and v2 caches. Set `WORKERS=4` to test the four-worker
profile. Per-run evidence is kept under `.anybuild/suite/runs/`.

The harness accepts an optional command to run after functional readiness
and exports the loopback `TARGET_URL` for it. The Artillery 2.0.34
`artillery.yml` scenario mixes the dynamic page and POST round trips.
