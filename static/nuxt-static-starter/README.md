# Nuxt static starter

Authored by Codex. The upstream template and lockfile come from
`https://github.com/wasmerio/examples` at `993bf9a55d3da307c5f2ecf4f4d716c63f44b764`.
The archive SHA-256 and build settings are in `inputs.env`.

Use the [static fixture build and test commands](../node-static-support/README.md).
The build writes `.anybuild/suite/package.webc`. The default test port is
`18233`. The test checks the starter's HTML, JavaScript MIME type,
cache headers, HEAD, gzip negotiation and equality with an emitted asset.
