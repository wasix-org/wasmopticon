# QR code toolkit

Codex authored this fixture around the starter from [wasmerio/examples](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-qr-toolkit)
at commit `993bf9a55d3da307c5f2ecf4f4d716c63f44b764`. The source archive
SHA-256 is `5f675f1eaee893c9e58466329ab790c1a59a827cd3c57036e4a49be54a81f11a`.

Generate a PNG using Segno, check its dimensions and media type, then send its bytes back to the OpenCV decoder. Verify the decoded text and the detected bounds. The checks use loopback and local inputs.

Build with Anybuild 0.33.3 and uvx 0.13.9. The wheel lock pins native
WASIX wheels as well as pure Python dependencies.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18111 ./test.sh
```
