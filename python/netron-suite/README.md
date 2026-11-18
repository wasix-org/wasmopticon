# Netron viewer

The Netron example and its 430-byte ONNX fixture are pinned to Wasmer's
examples monorepo revision `1da21d1232ce101832921e4d5c8d0a81adc6b98b`,
subdirectory `python-netron`. The build verifies the fixture's SHA-256 and
uses the hash-locked Netron 9.3.5 wheel. The viewer uses the address supplied
by the loopback harness and starts without opening a browser.

```sh
ANYBUILD_BIN=/path/to/anybuild WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=38383 ./test.sh
```

Use Anybuild 0.33.3 and uvx 0.13.9. The test checks viewer HTML, the exact sample bytes and
their content type, and the expected missing-model 404. For the Artillery
2.0.34 scenario, run `PORT=38383 WASMER_BIN=/path/to/wasmer ./serve.sh`
in a dedicated process.
