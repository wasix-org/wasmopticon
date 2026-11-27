import json
import sys
from http.client import HTTPConnection
from urllib.parse import urlencode, urlsplit


def request(origin, path, status, content_type):
    url = urlsplit(origin)
    connection = HTTPConnection(url.hostname, url.port, timeout=8)
    try:
        connection.request("GET", path)
        response = connection.getresponse()
        data = response.read()
        assert response.status == status, (path, response.status, data)
        assert response.headers.get_content_type() == content_type, (path, response.headers)
        return json.loads(data) if content_type == "application/json" else data
    finally:
        connection.close()


def main(origin):
    def search(query, limit=2, status=200):
        params = urlencode({"q": query, "k": limit})
        return request(origin, f"/api/search?{params}", status, "application/json")

    page = request(origin, "/", 200, "text/html")
    assert b'src="/wasmer-starter-ui.js"' in page

    for query, title in [
        ("undo a broken release", "Rollback"),
        ("my app is slow on the first request", "Cold start"),
        ("which websites may call my API from JavaScript", "CORS"),
    ]:
        body = search(query)
        assert body["query"] == query, body
        results = body["results"]
        assert 1 <= len(results) <= 2 and results[0]["title"] == title, body
        scores = [result["score"] for result in results]
        assert all(0.25 <= score <= 1.0 for score in scores), body
        assert scores == sorted(scores, reverse=True), body

    assert search("banana bread recipe")["results"] == []
    assert search("", status=400) == {"error": "q must be 1-500 characters"}
    assert search("cold start", "all", status=400) == {"error": "k must be an integer"}
    assert request(origin, "/missing", 404, "application/json") == {"error": "Not found"}
    print("Verified ONNX semantic ranking, unrelated-query filtering, and API validation")


if __name__ == "__main__":
    main(sys.argv[1])
