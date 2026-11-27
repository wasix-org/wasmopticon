import json
import sys
from http.client import HTTPConnection
from urllib.parse import urlparse

url = urlparse(sys.argv[1])


def request(method, path, expected):
    client = HTTPConnection(url.hostname, url.port, timeout=5)
    try:
        client.request(method, path)
        response = client.getresponse()
        body = response.read()
        assert response.status == expected, (method, path, response.status, expected)
        return response.headers, body
    finally:
        client.close()


for path in ("/", "/nested/route?check=1"):
    headers, body = request("GET", path, 200)
    assert headers.get_content_type() == "application/json"
    assert json.loads(body) == {"message": "Python app is running with Wasmer!"}

_, missing = request("HEAD", "/suite-missing", 404)
assert not missing
_, unsupported = request("POST", "/", 501)
assert b"Unsupported method" in unsupported
print("Verified stdlib HTTP JSON across paths, missing HEAD, and unsupported POST")
