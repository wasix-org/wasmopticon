# Gatsby starter

Authored by Codex. The upstream template and lockfile come from
`https://github.com/wasmer-examples/gatsby-wasmer-starter` at `265b49cce7bbbf60aa8f8f3790704631f54f5cc7`.
The archive SHA-256 and build settings are in `inputs.env`.

Use the [static fixture build and test commands](../node-static-support/README.md).
The build writes `.anybuild/suite/package.webc`. The default test port is
`18230`. The test checks the starter's HTML, JavaScript MIME type,
cache headers, HEAD, gzip negotiation and equality with an emitted asset.
