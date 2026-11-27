import sys
from http.client import HTTPConnection
from urllib.parse import urlparse

url = urlparse(sys.argv[1])


def request(method, path, status):
    client = HTTPConnection(url.hostname, url.port, timeout=5)
    try:
        client.request(method, path)
        response = client.getresponse()
        body = response.read()
        assert response.status == status, (method, path, status, response.status)
        return response.headers, body
    finally:
        client.close()


headers, body = request("GET", "/", 200)
greeting = "Hello, from Flask in Wasmer Edge 🚀".encode()
assert body == greeting
assert headers.get_content_type() == "text/html"
assert headers.get_content_charset() == "utf-8"

head, body = request("HEAD", "/", 200)
assert int(head["Content-Length"]) == len(greeting) and body == b""
options, _ = request("OPTIONS", "/", 200)
assert {method.strip() for method in options["Allow"].split(",")} == {"GET", "HEAD", "OPTIONS"}
_, missing = request("GET", "/suite-missing", 404)
assert b"<h1>Not Found</h1>" in missing
_, unsupported = request("POST", "/", 405)
assert b"<h1>Method Not Allowed</h1>" in unsupported
print("Verified Flask UTF-8 greeting, HEAD, OPTIONS, 404 and 405")
