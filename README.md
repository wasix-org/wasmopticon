# wasmopticon

A collection of projects compiling to Webassembly, primarily used for testing
across the Wasmer product stack (Wasmer runtime, Wasmer Edge, ...).

## Run the WASIX fixture suite

The functional runner, authored by Codex, needs Python 3.11+, GNU `timeout`
and each fixture's documented tools. Give it one or both Wasmer binaries.
Use a C API-enabled v2 binary for embedded Edge.js and point
`--registry-dir` at the offline WebC registry required by those fixtures.

```sh
./wasix-suite.py --v1 /path/to/wasmer-v1 --v2 /path/to/wasmer-v2 \
  --registry-dir /path/to/local/registry --jobs 2 --output .suite/full-run
```

The runner reuses existing WebCs by default. Add `--build` to build each
selected package once, using v1 when both lanes are supplied. Both lanes
then test that package, and the runner verifies its hash before and after
each test. It allocates distinct loopback ports and gives each lane its own
compiled cache. Use `--list` to preview cases and repeat `--filter` to
select fixture substrings or globs. The default is one job and one extra
attempt after a timeout. Set `--retry-on-timeout 0` to disable retries.

[wasix-suite.toml](wasix-suite.toml) lists the fixtures with Docker
requirements, non-default package paths, variants, profiles or timeouts.
Docker cases are skipped if the required daemon access is unavailable.
The output directory contains `results.md`, `results.json`, and test logs.
The runner exits nonzero for a failure or exhausted timeout.
