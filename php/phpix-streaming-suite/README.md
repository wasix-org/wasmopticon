# PHPix streaming suite

Authored by Codex. This fixture uses the PHPix 8.4 32-bit runtime graph
pinned by the sibling PHPix starter. The original fixture endpoint
flushes two lines with a two-second wait between them. The HTTP test
reads both lines from a single response and checks that the server
delivered the first flush before the second.

Use Anybuild 0.33.3 to create `.anybuild/suite/package.webc`. Test the
same package on both runtimes.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 PORT=18239 ./test.sh
WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 PORT=18239 ./test.sh
```
