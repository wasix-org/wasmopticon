from http.client import HTTPConnection
import json
import sys
from urllib.parse import urlencode, urlsplit

url = urlsplit(sys.argv[1])


def request(method, path, status, body=None):
    connection = HTTPConnection(url.hostname, url.port, timeout=25)
    try:
        headers = {"Content-Type": "application/x-www-form-urlencoded"} if body else {}
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        payload = response.read()
        assert response.status == status, (method, path, response.status, payload)
        return response.headers.get_content_type(), payload
    finally:
        connection.close()


route = "/api/pandoc-convert?"
text = "# Guest Pandoc\n\nThis is **Markdown**."
query = {"from": "markdown", "to": "html"}
mime, html = request("GET", route + urlencode({**query, "text": text}), 200)
assert mime == "text/plain"
assert b'<h1 id="guest-pandoc">Guest Pandoc</h1>' in html
assert b"<strong>Markdown</strong>" in html

query = {"from": "html", "to": "markdown"}
mime, markdown = request("POST", route + urlencode(query), 200, urlencode({"text": "<p>Hello <em>there</em>.</p>"}))
assert mime == "text/plain"
assert markdown.strip() == b"Hello *there*."

query = {"from": "unknownformat", "to": "html", "text": text}
mime, error = request("GET", route + urlencode(query), 400)
assert mime == "application/json"
assert 'Invalid input format! Got "unknownformat"' in json.loads(error)["error"]
print("Verified guest Pandoc conversions and unsupported format")
