import json
import sys
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import ProxyHandler, Request, build_opener

base_url = sys.argv[1]
opener = build_opener(ProxyHandler({}))


def request(path, status=200, name=None):
    data = None if name is None else urlencode({"name": name}).encode()
    try:
        response = opener.open(Request(base_url + path, data=data), timeout=8)
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.code == status, (path, response.code, body[:400])
        assert response.headers.get_content_type() == "application/json", response.headers
        return json.loads(body)


assert request("/") == {"mariadb": True}
assert request("/groups/") == {"groups": []}
committed = "Committed fixture"
created = request("/groups/create/", 201, committed)
assert created["id"] > 0 and created["name"] == committed and created["rolled_back"] is False
assert request("/groups/") == {"groups": [committed]}

rolled_back = "Rolled back fixture"
rolled = request("/groups/rollback/", 200, rolled_back)
assert rolled["id"] > 0 and rolled["name"] == rolled_back and rolled["rolled_back"] is True
assert request("/groups/") == {"groups": [committed]}

assert request("/groups/create/", 409, committed) == {"error": "Group name already exists."}
assert request("/groups/") == {"groups": [committed]}
print("Verified migrated Django ORM commit, rollback, and duplicate rejection on MariaDB")
