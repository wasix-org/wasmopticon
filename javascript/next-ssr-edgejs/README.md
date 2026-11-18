# Next.js SSR on embedded QuickJS Edge.js

Based on the [Next.js SSR starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-next-ssr).
The homepage renders a request-specific probe value and uses local system
fonts. The npm lock pins the template dependencies and next-bundle 1.0.0.
Node 26.13.1 and npm 11.20.0 do the build. Anybuild maps the guest Node
command to Edge.js QuickJS 0.2.5.

```sh
ANYBUILD_BIN=/path/to/anybuild-0.33.3 WASMER_BIN=/path/to/wasmer ./build.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer \
  WASIX_LANE=v2 PORT=18882 ./test.sh
```

The offline registry needs the WebCs in `registry.sha256`. The test checks
two distinct request-time HTML values and fetches an emitted JavaScript
asset. Use the released Wasmer executable and `WASIX_LANE=v1` to compare
on the same WebC. Logs are under `.anybuild/suite/`.

For load, start `serve.sh` with the same variables and explicit per-lane
`WASMER_DIR` and `WASMER_CACHE_DIR`. Use Artillery 2.0.34 and
`artillery.yml` against the loopback endpoint.
