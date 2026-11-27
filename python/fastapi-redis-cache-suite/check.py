from contextlib import closing
import http.client
import json
import sys
import time
from urllib.parse import urlsplit

endpoint = urlsplit(sys.argv[1])


def request(client, method, path, status, expected, body=None):
    headers = {}
    if body is not None:
        body = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    client.request(method, path, body, headers)
    response = client.getresponse()
    data = response.read()
    assert response.status == status, (method, path, response.status, data)
    assert response.headers.get_content_type() == "application/json"
    assert json.loads(data) == expected, (method, path, data)


target = {"key": "expires", "value": "cache ☃"}
control = {"key": "persistent", "value": "kept"}
miss = {"detail": "Cache miss"}
ttl = 4

with closing(http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)) as client:
    request(client, "GET", "/", 200, {"ready": True})
    request(client, "GET", "/cache/expires", 404, miss)
    for item in (target, control):
        path = "/cache/" + item["key"]
        request(client, "PUT", path, 200, item, {"value": item["value"]})
        request(client, "GET", path, 200, item)
    request(client, "POST", f"/cache/expires/expire?seconds={ttl}", 200, {"key": "expires", "expires_in": ttl})
    request(client, "GET", "/cache/expires", 200, target)
    time.sleep(ttl + 0.25)
    request(client, "GET", "/cache/expires", 404, miss)
    request(client, "GET", "/cache/persistent", 200, control)

print("Verified Redis SET, GET, EXPIRE, post-expiry miss, and unexpired control")
