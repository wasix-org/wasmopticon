# FFmpeg frame grabber fixture

Codex authored this fixture. It uses the `python-ffmpeg` template from
`wasmerio/examples` at `993bf9a55d3da307c5f2ecf4f4d716c63f44b764`.
The source archive SHA-256 is
`5f675f1eaee893c9e58466329ab790c1a59a827cd3c57036e4a49be54a81f11a`.
[Upstream template](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-ffmpeg)

The fixture adds a multipart upload route that shares the template's
FFprobe and frame extraction code. The test generates a four-frame Y4M
video locally, verifies that two timestamps yield distinct JPEGs of the
expected dimensions, and checks errors for an out-of-range seek and a
malformed upload.

Both tools run inside guest Python. The build verifies
`wasmer/ffmpeg@=1.0.5` and the extracted FFmpeg and FFprobe atoms against
the hashes in [build.sh](build.sh). Startup preloads both tools within
the readiness deadline to accommodate cold compilation.

Build with Anybuild 0.33.3 and uvx 0.13.9.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18122 ./test.sh
```
