# Hugo theme sample

Authored by Codex. The five variants use the Hugo Extended 0.121.2
binary pinned by the sibling Hugo starter and static-web-server 2.44.0.
The catalog paths and verified theme archives are listed in
`themes.tsv`. PaperMod and m10c use earlier upstream revisions compatible
with the pinned Hugo version.

Every variant serves the generated home, tag archive, RSS feed and 404.
The feature checks cover Mainroad's post thumbnail, Ink's dark stylesheet,
PaperMod's JSON search index, m10c's compiled Sass and Photophobia's
resized image.

```sh
WASMER_BIN=/path/to/wasmer-v1 ./build.sh paper-mod
WASMER_BIN=/path/to/wasmer-v1 ./test.sh paper-mod
WASMER_BIN=/path/to/wasmer-v2 ./test.sh paper-mod
```

Each variant's WebC is at `.suite/<variant>/.anybuild/suite/package.webc`.
Use `PORT` to override the variant's loopback test port.
