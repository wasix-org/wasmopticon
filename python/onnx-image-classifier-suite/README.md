# ONNX Image Classifier

This fixture uses the pinned [Wasmer image classifier template](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-onnx-image-classifier). Its source archive SHA-256 is `5f675f1eaee893c9e58466329ab790c1a59a827cd3c57036e4a49be54a81f11a`.

The app performs CPU inference with MobileNetV2 and the guest builds of ONNX Runtime, NumPy, and Pillow. The build downloads the model and labels from the pinned revision and checks their SHA-256 hashes. It also checks the vendored JPEGs, which the HTTP test fetches, verifies, and uploads for inference. The test checks both top labels, ranked confidences, and invalid image rejection.

Build with Anybuild 0.33.3, uvx 0.13.9, and Wasmer on `PATH`.

```sh
./build.sh
READY_TIMEOUT=180 PORT=18120 WASMER_BIN=wasmer ./test.sh
```

Codex authored the suite wrapper and checks. The upstream template and model use Apache 2.0. The sample photographs by Stefan van der Walt and Rachel Michetti are distributed under CC0. [Upstream license and source attribution](https://github.com/wasmerio/examples/blob/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-onnx-image-classifier/README.md#license-and-sources)
