import re
import sys
from concurrent.futures import ThreadPoolExecutor
from http.client import HTTPConnection
from http.cookiejar import CookieJar
from threading import Barrier
from urllib.error import HTTPError
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPCookieProcessor, ProxyHandler, Request, build_opener

base_url = sys.argv[1]
cookies = CookieJar()
opener = build_opener(ProxyHandler({}), HTTPCookieProcessor(cookies))


def request(path, status=200, fields=None):
    data = None if fields is None else urlencode(fields).encode()
    try:
        response = opener.open(Request(base_url + path, data=data), timeout=8)
    except HTTPError as error:
        response = error
    with response:
        body = response.read().decode()
        assert response.code == status, (path, status, response.code, body[:400])
        return response.geturl(), response.headers, body


def csrf_token(body):
    token = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', body)
    assert token, "CSRF field missing"
    return token.group(1)


admin = "/admin/"
login = admin + "login/?next=/admin/"
_, headers, page = request(login)
assert headers.get_content_type() == "text/html"
assert "Django administration" in page and 'name="username"' in page
credentials = {"username": "suite-admin", "password": "local-fixture-password"}
_, _, rejected = request(login, 403, credentials)
assert "CSRF verification failed" in rejected

url, _, home = request(login, fields={**credentials, "csrfmiddlewaretoken": csrf_token(page)})
assert url == base_url + admin and "Site administration" in home
groups = admin + "auth/group/"
_, _, form = request(groups + "add/")
name = "WASIX SQLite round trip"
url, _, _ = request(groups + "add/", fields={"name": name, "csrfmiddlewaretoken": csrf_token(form)})
assert url == base_url + groups
_, _, listing = request(groups)
assert name in listing

parallel_token = csrf_token(request(groups + "add/")[2])
cookie_request = Request(base_url + groups + "add/")
cookies.add_cookie_header(cookie_request)
cookie_header = cookie_request.get_header("Cookie")
assert cookie_header and "sessionid=" in cookie_header
names = {f"WASIX concurrent group {index:02}" for index in range(10)}
start = Barrier(20, timeout=5)
address = urlsplit(base_url)


def exercise_group(index):
    client = HTTPConnection(address.hostname, address.port, timeout=18)
    try:
        start.wait()
        if index % 2 == 0:
            body = urlencode(
                {"name": f"WASIX concurrent group {index // 2:02}", "csrfmiddlewaretoken": parallel_token}
            )
            headers = {"Cookie": cookie_header, "Content-Type": "application/x-www-form-urlencoded"}
            client.request("POST", groups + "add/", body, headers)
            response = client.getresponse()
            page = response.read()
            assert (response.status, response.headers.get("Location")) == (302, groups), (
                index, response.status, page[:400]
            )
        else:
            client.request("GET", groups, headers={"Cookie": cookie_header})
            response = client.getresponse()
            page = response.read().decode()
            assert response.status == 200 and name in page, (index, response.status, page[:400])
    finally:
        client.close()


with ThreadPoolExecutor(max_workers=20) as workers:
    list(workers.map(exercise_group, range(20)))

_, _, listing = request(groups)
assert set(re.findall(r"WASIX concurrent group \d{2}", listing)) == names
assert name in listing and re.search(r"\b11 groups\b", listing)
print("Verified 20 parallel Django admin requests, 10 unique SQLite writes, and a consistent count of 11 groups")

_, static_headers, hello = request("/static/hello.txt")
assert static_headers.get_content_type() == "text/plain"
assert hello == ''
_, css_headers, css = request("/static/admin/css/base.css")
assert css_headers.get_content_type() == "text/css"
assert "--primary" in css
_, _, missing = request("/suite-missing", 404)
assert "Not Found" in missing
print("Verified Django admin login, CSRF, SQLite group creation and readback, static files, and 404")
