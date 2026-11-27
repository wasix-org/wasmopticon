import concurrent.futures
import http.client
import json
import sys
from http.cookies import SimpleCookie
from urllib.parse import urlencode

port = int(sys.argv[1])
count = 20


def request(method, body=None, cookie=None):
    headers = {}
    if body is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    if cookie is not None:
        headers["Cookie"] = cookie
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    try:
        conn.request(method, "/session.php", body=body, headers=headers)
        response = conn.getresponse()
        data = response.read()
        if response.status != 200:
            raise RuntimeError(f"{method} returned HTTP {response.status}: {data!r}")
        return json.loads(data), response.getheader("Set-Cookie")
    finally:
        conn.close()


def write(index):
    value = f"session-{index}"
    result, header = request("POST", urlencode({"value": value}))
    cookie = SimpleCookie(header)["PHPSESSID"].value
    assert result == {"id": cookie, "value": value, "writes": 1}, result
    return cookie, value


def read(entry):
    cookie, value = entry
    result, _ = request("GET", cookie=f"PHPSESSID={cookie}")
    assert result == {"id": cookie, "value": value, "writes": 1}, result


with concurrent.futures.ThreadPoolExecutor(max_workers=count) as pool:
    results = list(pool.map(write, range(count)))
    assert len({cookie for cookie, _ in results}) == count
    list(pool.map(read, results))
print(f"Verified {count} parallel session writes and {count} reads with separate cookies")
