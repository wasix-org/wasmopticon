# Semantic search suite

Codex prepared this fixture from the [Wasmer semantic search starter](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-semantic-search).
The source is pinned to commit `993bf9a55d3da307c5f2ecf4f4d716c63f44b764`.
The source archive SHA-256 is
`5f675f1eaee893c9e58466329ab790c1a59a827cd3c57036e4a49be54a81f11a`.

The build fetches the model, tokenizer and precomputed document
embeddings from that commit and verifies them with `inputs.sha256`.
The guest reads all model files locally. The wheel lock pins NumPy,
ONNX Runtime and tokenizers for CPython 3.13 on WASIX. The fixture
honors the shared harness's `HOST` setting for its HTTP listener.

```sh
WASMER_BIN=/path/to/wasmer ./build.sh
WASMER_BIN=/path/to/wasmer PORT=18121 ./test.sh
```

The test checks top-ranked glossary entries for three paraphrased
queries, score ordering, filtering for an unrelated query, and request
validation. The expected ranking uses the upstream model and document
index.
