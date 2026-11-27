# Static Website Registry template fixture

This fixture serves the pinned Wasmer Static Website template's original
homepage and photographs. Anybuild 0.33.3 stages the `public/` tree and
maps the server command to the exact Registry package
`wasmer/static-web-server@1.1.0`. The build keeps the upstream web-server
settings and supplies the document root, bind address and port through
the package command and local test.
[Pinned template source](https://github.com/wasmer-examples/static-website/tree/ccd67d29d46bdc38cfe6cd0275469fa8af17adc5)

Requires Bash, coreutils, `flock`, tar, Python 3, curl, Anybuild 0.33.3 and
a Wasmer CLI with Cranelift.

```sh
ANYBUILD_BIN=/path/to/anybuild WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer ./test.sh
```

The build verifies the checksums of the source archive and server WEBC.
Set `STATIC_WEB_SERVER_WEBC` to reuse a local copy of the server WEBC.
`test.sh` runs `.anybuild/suite/package.webc` with the local server
dependency. It verifies the HTML and JPEG bytes, conditional and range
responses, and the missing-page status. Set `PORT` to select a loopback
port and `READY_TIMEOUT` to adjust the readiness deadline in seconds.
