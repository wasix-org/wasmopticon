# Local load tests

Install the exact Artillery version and its locked dependencies with Node
22.18.0 or newer.

```sh
npm ci --prefix perf --ignore-scripts --no-audit --no-fund
ARTILLERY_DISABLE_TELEMETRY=1 perf/node_modules/.bin/artillery --version
```

Start the application with its fixture's loopback launch command. Use the
fixture's scenario and port. For example, the static scenario defaults to
port 18081 and checks HTML, assets, rewrites and a byte range.

```sh
mkdir -p perf/.suite
ARTILLERY_DISABLE_TELEMETRY=1 perf/node_modules/.bin/artillery run \
  --platform local --target http://127.0.0.1:18081 \
  --output perf/.suite/static-smoke.json perf/static-web-server.yml
```

Keep scenario routes
relative, set `followRedirect: false` for HTTP requests and use explicit
status and body assertions. For JSON, use a JMESPath equality expression.

## Paired Linux runs

`run-pair.py` needs Python 3.11+, cgroup v2, a systemd user session,
`taskset`, and GNU time. Pass a JSON spec with:

- `package` and `sha256` for one local WebC shared across lanes.
- `scenario`, `artillery`, `cwd` and `cache` paths. The runner creates
  separate lane cache directories beneath `cache` and uses fresh
  `WASMER_DIR` paths per run.
- `port`, `ready_path` and `ready_body` for the loopback readiness check.
- `server_cpus` and `client_cpus` taskset lists.
- `lanes` with `v1` and `v2` keys, each having an absolute `binary` and an
  argument array `launch`. Use offline runs and explicit loopback bindings.

```sh
python3 perf/run-pair.py /path/to/static.json sweep /path/to/evidence/static-sweep \
  --rates 5 15 30
```

`smoke` is a six-second validation per lane. `sweep` runs a 30-second
smoke, 60-second warmup and individual 60-second plateaus. `soak` runs a
60-second warmup, then a 30-minute load and five minutes idle by default.
The final probe checks continued responsiveness. `--reverse` changes
lane order and `--wait-lock` queues behind the holder of the benchmark
lock. The runner verifies the WebC and scenario hashes for both lanes.
Save reports to a new evidence directory for each invocation.

Review the Artillery report counters and the exit files, along with the
sampled CPU, RSS, cgroup memory and host memory headroom. A complete
harness run can contain HTTP errors or failed scenario assertions.
