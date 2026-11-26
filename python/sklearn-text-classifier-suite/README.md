# scikit-learn text classifier

This fixture is adapted from the pinned [Wasmer text classifier template](https://github.com/wasmerio/examples/tree/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-sklearn-classifier). Its source archive SHA-256 is `5f675f1eaee893c9e58466329ab790c1a59a827cd3c57036e4a49be54a81f11a`.

The Flask app trains the original TF-IDF and logistic regression pipeline at startup. The test checks the web interface, classifies two known messages, and verifies the probabilities, positive word contributions, and validation error. The wheel lock pins the WASIX builds of NumPy, SciPy, and scikit-learn as well as the pure Python dependencies.

Build with Anybuild 0.33.3, uvx 0.13.9, and Wasmer on `PATH`. Set `WASMER_BIN` to choose the runtime and optionally set `PORT` to an available loopback port. Set `READY_TIMEOUT=220` for a cold WASIX v2 run on a shared host, where compiling the native extensions can take over 90 seconds.

```sh
./build.sh
PORT=18112 WASMER_BIN=wasmer ./test.sh
```

Codex authored the suite wrapper and checks. The upstream code is MIT licensed. The included CSV is derived from the SMS Spam Collection by Tiago A. Almeida and José María Gómez Hidalgo and distributed under CC BY 4.0. [Upstream license and data attribution](https://github.com/wasmerio/examples/blob/993bf9a55d3da307c5f2ecf4f4d716c63f44b764/python-sklearn-classifier/README.md#license-and-data)
