import json
import sys
import time
from http.client import HTTPConnection
from urllib.parse import urlsplit


def request(origin, method, path, status, payload=None):
    url = urlsplit(origin)
    connection = HTTPConnection(url.hostname, url.port, timeout=4)
    try:
        body = json.dumps(payload) if payload is not None else None
        headers = {"Content-Type": "application/json"} if body is not None else {}
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        data = response.read()
        assert response.status == status, (method, path, response.status, data)
        assert response.headers.get_content_type() == "application/json", (path, response.headers)
        return json.loads(data)
    finally:
        connection.close()


def main(origin):
    assert request(origin, "GET", "/", 200) == {"redis": "ready"}
    assert request(origin, "GET", "/results", 200) == []

    for job_id, value in (
        ("first", "alpha"),
        ("second", "bravo"),
        ("first", "ignored duplicate"),
        ("last", "charlie"),
    ):
        assert request(origin, "POST", "/jobs", 202, {"id": job_id, "value": value}) == {
            "id": job_id,
        }

    expected = [
        {"id": "first", "result": "ALPHA"},
        {"id": "second", "result": "BRAVO"},
        {"id": "last", "result": "CHARLIE"},
    ]
    deadline = time.monotonic() + 12
    while True:
        observed = request(origin, "GET", "/results", 200)
        if observed and observed[-1]["id"] == "last":
            assert observed == expected, observed
            break
        assert time.monotonic() < deadline, ("Timed out waiting for worker results", observed)
        time.sleep(0.1)
    print("Verified Redis BLPOP worker FIFO results and duplicate job idempotence")


if __name__ == "__main__":
    main(sys.argv[1])
