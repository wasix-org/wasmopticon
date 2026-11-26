import json
import struct
import sys
from http.client import HTTPConnection
from urllib.parse import urlparse

url = urlparse(sys.argv[1])


def post(path, data, content_type, status=200):
    client = HTTPConnection(url.hostname, url.port, timeout=20)
    try:
        client.request("POST", path, data, {"Content-Type": content_type})
        response = client.getresponse()
        body = response.read()
        assert response.status == status, (path, status, response.status, body[:300])
        return response.headers, body
    finally:
        client.close()


text = "WASIX QR encode and decode"
headers, png = post("/api/generate", json.dumps({"text": text, "format": "png", "scale": 6, "error": "H"}), "application/json")
assert headers.get_content_type() == "image/png"
assert headers["Content-Disposition"] == 'inline; filename="qr-code.png"'
assert png.startswith(b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR")
width, height = struct.unpack_from(">II", png, 16)
assert width == height and width > 100 and width % 6 == 0
_, decoded = post("/api/decode", png, "image/png")
decoded = json.loads(decoded)
assert decoded["text"] == text
assert decoded["image"] == {"width": width, "height": height}
assert len(decoded["corners"]) == 4
assert decoded["box"]["width"] > 0 and decoded["box"]["height"] > 0
_, error = post("/api/generate", '{"text":""}', "application/json", 400)
assert "Text must be" in json.loads(error)["error"]
print("Verified QR PNG properties, OpenCV decode round-trip, and validation")
