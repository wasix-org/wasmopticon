from contextlib import closing
from hashlib import sha256
import http.client
import sys
from urllib.parse import urlsplit


def request(connection, path, status, content_type=None):
    connection.request("GET", path)
    response = connection.getresponse()
    body = response.read()
    assert response.status == status, (path, response.status)
    if content_type is not None:
        assert response.headers.get_content_type() == content_type, response.headers
    print(f"{status} {path}")
    return body


endpoint = urlsplit(sys.argv[1])
with closing(http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)) as client:
    home = request(client, "/", 200, "text/html")
    assert b"<title>Netron</title>" in home
    assert b'<meta name="file" content="/data/tiny-classifier.onnx">' in home
    data = request(client, "/data/tiny-classifier.onnx", 200, "application/octet-stream")
    assert len(data) == 430
    assert sha256(data).hexdigest() == "ffb0974440daf6fee3f59072a467194d920481b3afb0ff0606e38be0e4ffd3cf"
    request(client, "/data/missing.onnx", 404)
