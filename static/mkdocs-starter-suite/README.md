# MkDocs starter fixture

Codex authored this fixture. It renders the MkDocs starter at
`975b9a87074cdee9fc8d96d4f7afe6834f929aed` with MkDocs 1.6.1 and serves
the generated site with Static Web Server 2.44.0. The starter archive and
server package are pinned by SHA-256 in [build.sh](build.sh).
[Upstream source](https://github.com/wasmer-examples/mkdocs-wasmer-starter/tree/975b9a87074cdee9fc8d96d4f7afe6834f929aed)

Build on Linux x86-64 or ARM64 with CPython 3.12, uv 0.13.9, Anybuild
0.33.3, Wasmer, and the standard Bash, curl, coreutils, flock, and tar
tools. The dependency lock contains hashes for host wheels. The site
build and WebC staging use the same fixed timestamp.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18115 ./test.sh
```

Build inputs stay in `.suite/`. Set `STATIC_WEB_SERVER_WEBC` to reuse
the pinned server package. The build writes `.anybuild/suite/package.webc`.
The test checks the rendered Markdown, stylesheet, generated search
index, and custom 404 page on loopback. Set `READY_TIMEOUT` to override
the startup deadline in seconds.
