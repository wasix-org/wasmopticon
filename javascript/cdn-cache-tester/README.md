# CDN Cache Tester

A small JavaScript app for checking Wasmer Edge CDN cache behaviour.

Available routes:

- `/current-time/30s`
- `/current-time/5m`
- `/current-time/1h`
- `/current-time/1d`
- `/test` runs browser-side cache behaviour tests and dynamically reports success or failure
- `/uat` walks an operator through dashboard and CLI CDN enable, purge, and disable acceptance tests
- `/uat-data` returns a 24-hour cacheable response used by the UAT wizard

Each current-time response includes an ISO timestamp, Unix timestamp, unique origin request ID, and a `Cache-Control: public, max-age=<seconds>` header. The client-side test runner verifies that the CDN caches a response, that `Cache-Control: no-cache` on a client request bypasses a primed response, and that a cached `30s` response is replaced after waiting 31 seconds.

The app is deployed with CDN caching disabled so the UAT wizard can verify the initial state before guiding the operator through dashboard and CLI controls. All checks are driven directly by browser JavaScript; the server only returns the cacheable diagnostic response. Enablement and disablement checks retry the same cache key with short delays and a bounded attempt count to allow CDN configuration changes to propagate.

## Run locally

```bash
npm start
```

Visit <http://localhost:8080>. Cache reuse tests will fail locally because no CDN is present.

## Deploy

```bash
wasmer deploy --build-remote
```
