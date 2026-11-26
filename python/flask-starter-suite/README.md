# Flask starter

Codex authored this fixture around the Flask starter from
[wasmer-examples/flask-wasmer-starter](https://github.com/wasmer-examples/flask-wasmer-starter/tree/de3ef45ea17e054d234a77d3a02d625319e9f9df)
at `de3ef45ea17e054d234a77d3a02d625319e9f9df`. The template inventory leaves
the branch unset. This is the repository's HEAD at fixture creation.
The GitHub source archive SHA-256 is
`e8fced5c2c93391d1722a178aaf4a516726228e370c850b4d335ac7e7ddf958f`.

The original Flask app runs on a configurable loopback port. The test
checks the UTF-8 greeting, HEAD metadata, implicit OPTIONS, a missing
route, and a rejected POST.

Build with Anybuild 0.33.3 and uvx 0.13.9 on PATH. The WASIX wheel lock
keeps Flask 3.1.2 and pins its transitive dependencies.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18101 ./test.sh
```
