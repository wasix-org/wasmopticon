# Static Web Server fixture

The Field Guide site serves HTML, CSS and JavaScript from a packaged document
root. Static Web Server rewrites `/learn` to a directory index, redirects
`/old-guide` while preserving its query string, and returns a custom 404.

The server comes from [`wasmer/static-web-server@2.44.0`](https://wasmer.io/wasmer/static-web-server).
`build.sh` checks the registry WEBC's SHA-256, extracts the `webserver` atom
and lets Anybuild 0.33.3 stage that module and the site. This uses Anybuild's
direct Wasm module support because its package mapper does not list 2.44.0.

Requires Bash, Anybuild 0.33.3, Wasmer with Cranelift, coreutils, `flock`,
Python 3 and curl. Run these commands from this directory.

```sh
ANYBUILD_BIN=/path/to/anybuild WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer ./test.sh
```

Set `STATIC_WEB_SERVER_WEBC` to use a local copy of the pinned registry
download. `test.sh` starts `.suite/package.webc` on loopback and cleans up
when it exits. It selects an available port by default. Set `PORT` to use a
specific port and `READY_TIMEOUT` to change the startup deadline in seconds.
The script uses `--publish` when the CLI provides it and `--net` on the
released WASIX v1 CLI.
