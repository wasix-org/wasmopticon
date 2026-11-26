# Laravel Blade starter suite

Fixture authored by Codex. The `laravel-blade-starter` template comes from
[wasmerio/examples](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/php-laravel-starter)
under `php-laravel-starter`. The build verifies the source in `inputs.env`
and installs production packages from the upstream `composer.lock`.
The WebC uses the PHPix 8.4 32-bit runtime pinned by the sibling PHPix starter.

Use Anybuild 0.33.3, native PHP 8.4 and Composer 2. The build writes
`.anybuild/suite/package.webc`. An existing source archive can be passed
through `EXAMPLES_ARCHIVE` and is verified before extraction.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 PORT=18210 ./test.sh
WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 PORT=18210 ./test.sh
```

The test checks the upstream Blade page, API status, health and 404. A
fixture-only Blade form rejects a missing CSRF token and accepts a valid
one. The POST applies the upstream migrations to a fresh guest SQLite
file and writes a row. A later request reads the row using the email
stored in the browser session. Logs and responses are in
`.anybuild/suite/runs/`.
