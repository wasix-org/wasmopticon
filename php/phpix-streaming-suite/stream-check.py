import sys
import time
from http.client import HTTPConnection

port = int(sys.argv[1])
connection = HTTPConnection("127.0.0.1", port, timeout=5)
try:
    started = time.monotonic()
    connection.request("GET", "/stream.php")
    response = connection.getresponse()
    assert response.status == 200, response.status
    assert response.getheader("Content-Type").split(";")[0] == "text/plain"
    assert response.getheader("Cache-Control") == "no-store"
    assert response.readline() == b"start\n"
    first = time.monotonic()
    assert response.readline() == b"end\n"
    second = time.monotonic()
    assert response.read() == b""
    print(f"first={first - started:.3f}s last={second - started:.3f}s gap={second - first:.3f}s")
    assert second - first >= 1.0, "PHPix buffered the first flush"
finally:
    connection.close()
