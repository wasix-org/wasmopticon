# Symfony LTS starter suite

Fixture authored by Codex. The `symfony-lts-starter` template comes from
[wasmerio/examples](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/php-symfony-starter)
under `php-symfony-starter`. The build verifies the source in `inputs.env`,
installs production packages from the upstream `composer.lock`, and uses
the template's production environment dump. The WebC uses the PHPix 8.4
32-bit runtime pinned by the sibling PHPix starter.

Use Anybuild 0.33.3, native PHP 8.4 and Composer 2. The build writes
`.anybuild/suite/package.webc`. An existing source archive can be passed
through `EXAMPLES_ARCHIVE` and is verified before extraction.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh
WASMER_BIN=/path/to/wasmer-v1 WASIX_LANE=v1 PORT=18220 ./test.sh
WASMER_BIN=/path/to/wasmer-v2 WASIX_LANE=v2 PORT=18220 ./test.sh
```

The test checks the rendered controller page, the JSON route and its
content type, the starter UI asset, and the Symfony 404 page. Logs and
responses are in `.anybuild/suite/runs/`.
