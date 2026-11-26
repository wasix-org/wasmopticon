# Static-web-server template sample

Authored by Codex. The three inputs come from the static-web-server
JavaScript template catalog. Each variant has an independent frozen
package and loopback test.

| Variant | Coverage | Default port |
| --- | --- | --- |
| `app-client-side-router` | A direct request for a nested client route falls back to the demo shell | 18235 |
| `duckdb-csv-explorer` | HEAD and byte-range delivery for the large DuckDB WebAssembly asset | 18236 |
| `bentopdf` | Exact responses across a multi-file export | 18237 |

Use the [static fixture toolchain](../node-static-support/README.md).

```sh
WASMER_BIN=/path/to/wasmer ./build.sh duckdb-csv-explorer
WASMER_BIN=/path/to/wasmer PORT=18236 ./test.sh duckdb-csv-explorer
```

The variant's workspace and artifact are under `.suite/<variant>/`.
