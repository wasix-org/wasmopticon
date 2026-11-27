# React streaming SSR on Edge.js

Codex authored this local regression fixture using the repository's Node HTTP
fixture layout. React and React DOM are pinned to 19.2.3, matching the
Next.js SSR fixture in this suite.

The client reads the React shell and Suspense fallback in HTTP/1.1 chunks
before it sends a second request to release the suspended component. It then
checks the deferred markup, the terminating HTTP chunk, and server health.
The release request makes the ordering test independent of elapsed time.
[React server renderer](https://react.dev/reference/react-dom/server/renderToPipeableStream)

Build with Node 26.13.1, npm 11.20.0, and Anybuild 0.33.3. The local
registry must contain the WebCs pinned in `registry.sha256`.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
REGISTRY_DIR=/path/to/registry WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 PORT=18388 ./test.sh
REGISTRY_DIR=/path/to/registry WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 PORT=18388 ./test.sh
```
