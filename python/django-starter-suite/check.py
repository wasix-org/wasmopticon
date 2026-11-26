import re
import sys
from http.cookiejar import CookieJar
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import HTTPCookieProcessor, ProxyHandler, Request, build_opener

base_url = sys.argv[1]
opener = build_opener(ProxyHandler({}), HTTPCookieProcessor(CookieJar()))


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

_, static_headers, hello = request("/static/hello.txt")
assert static_headers.get_content_type() == "text/plain"
assert hello == ''
_, css_headers, css = request("/static/admin/css/base.css")
assert css_headers.get_content_type() == "text/css"
assert "--primary" in css
_, _, missing = request("/suite-missing", 404)
assert "Not Found" in missing
print("Verified Django admin login, CSRF, SQLite group creation and readback, static files, and 404")
