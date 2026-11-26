import json
import sys
from hashlib import sha256
from http.client import HTTPConnection
from pathlib import Path
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])


def request(method, path, status, mime, data=None, headers=None):
    connection = HTTPConnection(url.hostname, url.port, timeout=15)
    try:
        connection.request(method, path, body=data, headers=headers or {})
        response = connection.getresponse()
        body = response.read()
        assert response.status == status, (path, response.status, body[:300])
        assert response.headers.get_content_type() == mime, (path, response.headers)
        return body
    finally:
        connection.close()


def upload(filename, image, status):
    boundary = "wasmopticon-onnx-image"
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="image"; filename="{filename}"\r\n'
        "Content-Type: image/jpeg\r\n\r\n"
    ).encode() + image + f"\r\n--{boundary}--\r\n".encode()
    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    payload = request("POST", "/api/classify", status, "application/json", body, headers)
    return json.loads(payload)


index = request("GET", "/", 200, "text/html")
assert b"ONNX Image Classifier" in index and b'data-sample="samples/cat.jpg"' in index
samples = {
    Path(path).name: digest for digest, path in (
        line.split() for line in Path("samples.sha256").read_text().splitlines()
    )
}
for sample, expected in (("cat.jpg", "cat"), ("coffee.jpg", "espresso")):
    image = request("GET", f"/samples/{sample}", 200, "image/jpeg")
    assert sha256(image).hexdigest() == samples[sample], sample
    result = upload(sample, image, 200)
    assert result["model"] == "mobilenetv2-12", result
    predictions = result["predictions"]
    assert len(predictions) == 5, result
    assert len({item["label"] for item in predictions}) == 5, result
    assert expected in predictions[0]["label"].lower(), result
    confidences = [item["confidence"] for item in predictions]
    assert all(0 <= score <= 1 for score in confidences), result
    assert confidences == sorted(confidences, reverse=True), result
    assert 0 < sum(confidences) <= 1.0001, result
    print(f'{sample}: {predictions[0]["label"]} ({confidences[0]:.4f})')

assert "not a readable image" in upload("bad.jpg", b"not JPEG", 400)["error"]
print("Verified both MobileNetV2 predictions, served input bytes, and invalid image rejection")
