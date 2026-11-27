# Laravel queue and scheduler

Authored by Codex. This fixture extends the pinned Laravel Blade starter
without changing its Composer lock. The HTTP endpoint dispatches a job
onto Laravel's database queue. A separate guest runs `queue:work --once`
and the HTTP endpoint verifies the job's side effect. A third guest
runs `schedule:run` and the test verifies that the every-minute task
wrote its own result. All guests mount the same temporary SQLite file.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 ./test.sh
WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 ./test.sh
```

The default HTTP port is 18260.
