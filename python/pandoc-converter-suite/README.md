# Pandoc converter fixture

Codex authored this fixture. It copies the FastAPI converter from the
`python-fastapi-pandoc-converter` directory at
`993bf9a55d3da307c5f2ecf4f4d716c63f44b764`. The source archive SHA-256 is
`5f675f1eaee893c9e58466329ab790c1a59a827cd3c57036e4a49be54a81f11a`.
[Pinned starter source](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-fastapi-pandoc-converter)

The build stages the executable atom from `wasmer/pandoc@=0.0.1` with the
guest app. The build verifies the downloaded WebC and extracted module
against separate SHA-256 pins. The FastAPI wrapper configures pypandoc to
launch that Wasm module inside the guest.

Build with Anybuild 0.33.3 and uvx 0.13.9.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18113 ./test.sh
```

The test converts Markdown to HTML and HTML to Markdown over loopback
HTTP. It also checks that the API reports an unsupported input format.
Startup checks the guest Pandoc version before binding. The readiness
deadline defaults to 180 seconds to allow for compiling the Pandoc atom
with a cold module cache.
