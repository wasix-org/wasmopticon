# CDN Cache Tester

A small JavaScript app for checking Wasmer Edge CDN cache behaviour.

Available routes:

- `/current-time/30s`
- `/current-time/5m`
- `/current-time/1h`
- `/current-time/1d`
- `/test` runs browser-side cache behaviour tests and dynamically reports success or failure

Each current-time response includes an ISO timestamp, Unix timestamp, unique origin request ID, and a `Cache-Control: public, max-age=<seconds>` header. The client-side test runner verifies that the CDN caches a response, that `Cache-Control: no-cache` on a client request bypasses a primed response, and that a cached `30s` response is replaced after waiting 31 seconds.

## Run locally

```bash
npm start
```

Visit <http://localhost:8080>. Cache reuse tests will fail locally because no CDN is present.

## Deploy

```bash
wasmer deploy --build-remote
```
