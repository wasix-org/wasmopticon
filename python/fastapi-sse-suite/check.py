import sys
import time
from http.client import HTTPConnection
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])
connection = HTTPConnection(url.hostname, url.port, timeout=8)
try:
    started = time.monotonic()
    connection.request("GET", "/events", headers={"Accept": "text/event-stream"})
    response = connection.getresponse()
    assert response.status == 200, response.status
    assert response.headers.get_content_type() == "text/event-stream", response.headers
    assert response.getheader("Cache-Control") == "no-store", response.headers

    arrivals = []
    for expected in (b"data: start\n", b"data: end\n"):
        assert response.readline() == b"event: progress\n"
        assert response.readline() == expected
        assert response.readline() == b"\n"
        arrivals.append(time.monotonic())

    assert response.read() == b""
    first, second = arrivals
    print(f"first={first - started:.3f}s last={second - started:.3f}s gap={second - first:.3f}s")
    assert second - first >= 1.0, "The first SSE event was buffered"
finally:
    connection.close()
