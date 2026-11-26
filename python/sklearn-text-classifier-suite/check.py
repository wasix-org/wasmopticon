import json
import math
import sys
from http.client import HTTPConnection
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])


def request(method, path, expected, payload=None):
    connection = HTTPConnection(url.hostname, url.port, timeout=8)
    try:
        headers = {"Content-Type": "application/json"} if payload is not None else {}
        body = None if payload is None else json.dumps(payload)
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        data = response.read()
        assert response.status == expected, (method, path, response.status, data[:300])
        return response.headers.get_content_type(), data
    finally:
        connection.close()


mime, html = request("GET", "/", 200)
assert mime == "text/html" and b"/static/wasmer-starter-ui.js" in html
mime, script = request("GET", "/static/wasmer-starter-ui.js", 200)
assert mime in ("application/javascript", "text/javascript") and b"customElements" in script

for text, expected in [
    ("WINNER! Claim your free prize now, call 09061701461", "spam"),
    ("See you at lunch", "ham"),
]:
    mime, body = request("POST", "/api/predict", 200, {"text": text})
    assert mime == "application/json"
    prediction = json.loads(body)
    probabilities = prediction["probabilities"]
    assert prediction["label"] == expected, prediction
    assert set(probabilities) == {"ham", "spam"}, prediction
    assert all(0 <= probability <= 1 for probability in probabilities.values()), prediction
    assert math.isclose(sum(probabilities.values()), 1.0), prediction
    assert max(probabilities, key=probabilities.get) == expected, prediction
    assert prediction["top_words"] and all(
        item["word"] and item["weight"] > 0 for item in prediction["top_words"]
    ), prediction

mime, body = request("POST", "/api/predict", 400, {"text": " "})
assert mime == "application/json"
assert json.loads(body) == {"error": 'Provide a non-empty "text" string.'}
print("Verified scikit-learn ham and spam predictions, probabilities, word contributions, and input validation")
