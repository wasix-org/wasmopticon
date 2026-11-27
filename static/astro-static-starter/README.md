# Astro static starter

Codex authored this fixture. It builds the registry template's exact
`js-astro-starter` root and original npm lock. Astro 7.4.11 exports the
home and about pages, the shared Wasmer UI JavaScript, and the favicon
to `dist/`. [Pinned upstream starter](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/js-astro-starter)

Use the [static fixture build and test commands](../node-static-support/README.md).
The WebC is written to `.anybuild/suite/package.webc`. The default test
port is 18397. The test verifies both pages, the missing-route response,
JavaScript bytes and MIME type, caching, HEAD, gzip, and the favicon MIME
type.
