# CDN Cache Tester

A small JavaScript app for checking Wasmer Edge CDN cache behaviour.

Available routes:

- `/current-time/30s`
- `/current-time/5m`
- `/current-time/1h`
- `/current-time/1d`
- `/test` runs browser-side requests against every cache route and dynamically reports success or failure

Each current-time response includes an ISO timestamp, Unix timestamp, unique origin request ID, and a `Cache-Control: public, max-age=<seconds>` header. The client-side test runner uses a fresh query parameter per run, requests each URL twice, and checks that the CDN reused the first origin response. It also waits 31 seconds and verifies that the `30s` response is replaced after its TTL expires.

## Run locally

```bash
npm start
```

Visit <http://localhost:8080>. Cache reuse tests will fail locally because no CDN is present.

## Deploy

```bash
wasmer deploy --build-remote
```
