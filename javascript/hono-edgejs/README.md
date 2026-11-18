# Hono on embedded QuickJS Edge.js

Based on the [Hono starter](https://github.com/wasmerio/examples/tree/1da21d1232ce101832921e4d5c8d0a81adc6b98b/js-hono).
The fixture keeps the upstream greeting and npm lock, adds a JSON echo, and
defaults to loopback. Node 24.13.2 and npm 11.8.0 are the build toolchain.
Anybuild maps the guest Node command to Edge.js QuickJS 0.2.5.

```sh
ANYBUILD_BIN=/path/to/anybuild-0.33.3 WASMER_BIN=/path/to/wasmer ./build.sh
REGISTRY_DIR=/path/to/local/registry WASMER_BIN=/path/to/wasmer \
  WASIX_LANE=v2 PORT=18880 ./test.sh
```

The offline registry needs the three WebCs under the paths in
`registry.sha256`. Run the same package with `WASIX_LANE=v1` and the released
Wasmer executable to compare. Functional runs keep logs under
`.anybuild/suite/`. For load, start `serve.sh` with the same variables and
explicit per-lane `WASMER_DIR` and `WASMER_CACHE_DIR`. Point pinned Artillery
2.0.34 at that loopback port with `artillery.yml`.
