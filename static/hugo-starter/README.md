# Hugo starter fixture

This fixture builds the Wasmer Hugo starter with its bundled Ananke theme.
Hugo Extended 0.121.2 supports the theme's
Sass and older template APIs. The build includes the upstream draft post
to exercise Hugo's preview output. Anybuild 0.33.3 stages the generated
site and the checksum-pinned Static Web Server 2.44.0 module.
[Pinned starter source](https://github.com/wasmer-examples/hugo-wasmer-starter/tree/098cecbf023c3f0522f15381fe34241eb43fb1b3)

Run on Linux amd64 or arm64 with Bash, coreutils, `flock`, tar, Python 3,
curl, Anybuild 0.33.3 and a Wasmer CLI with Cranelift.

```sh
ANYBUILD_BIN=/path/to/anybuild WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer ./test.sh
```

Build inputs stay in `.suite/`, and the package is written to
`.anybuild/suite/package.webc`. Set
`STATIC_WEB_SERVER_WEBC` to reuse an existing copy of the pinned server
package. The test checks the generated HTML, RSS, stylesheet, hero image
and custom 404 on a loopback port. Use `PORT` to choose a specific port
and `READY_TIMEOUT` to set the startup deadline in seconds.
