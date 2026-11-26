# Static app templates

Authored by Codex. These fixtures install and build the pinned Wasmer
catalog templates with host Node through Anybuild. The CDN template ships
its public media and HTML as source files, so its recipe copies them
directly. All variants run in static-web-server 2.44.0.

Use the [static fixture toolchain](../node-static-support/README.md).
The six supported variants are `excalidraw`, `it-tools`, `drawdb`,
`minipaint`, `piskel` and `cdn-starter`. Pins and test settings are in
the matching `.env` file.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh minipaint
WASMER_BIN=/path/to/wasmer PORT=18243 ./test.sh minipaint
```

Each output is under `.suite/<variant>/.anybuild/suite/package.webc`.
The tests check app HTML, routes or fallback, asset content types,
byte equality, HEAD and gzip. They also check worker and font assets
where the application ships them.
