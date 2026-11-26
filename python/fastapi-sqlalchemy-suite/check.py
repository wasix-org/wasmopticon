import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import ProxyHandler, Request, build_opener

phase, expected_path, base_url = sys.argv[1:]
expected_path = Path(expected_path)
opener = build_opener(ProxyHandler({}))


def request(method, path, status=200, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    headers = {} if data is None else {"Content-Type": "application/json"}
    try:
        response = opener.open(Request(base_url + path, data, headers, method=method), timeout=8)
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.code == status, (method, path, status, response.code, body[:400])
        if response.code == 204:
            return body
        if response.headers.get_content_type() == "application/json":
            return json.loads(body)
        return body


def utc_row(row):
    created_at = datetime.fromisoformat(row["created_at"])
    # The starter writes UTC. SQLite's DateTime representation drops the offset.
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    return {**row, "created_at": created_at.astimezone(timezone.utc)}


todos = "/api/todos"
if phase == "write":
    assert b"<code>sqlite</code>" in request("GET", "/")
    assert request("GET", todos) == []
    assert "detail" in request("POST", todos, 422, {"title": "   "})
    created = request("POST", todos, 201, {"title": "  WASIX todo  "})
    assert created["title"] == "WASIX todo" and created["done"] is False
    assert created["id"] > 0 and created["created_at"]
    listed = request("GET", todos)
    assert [utc_row(row) for row in listed] == [utc_row(created)], (listed, created)
    updated = request("PATCH", f'{todos}/{created["id"]}', payload={"title": "Updated todo", "done": True})
    assert utc_row(updated) == {**utc_row(created), "title": "Updated todo", "done": True}, updated
    assert b"<s>Updated todo</s>" in request("GET", "/")
    expected_path.write_text(json.dumps(updated))
    print("Verified FastAPI todo creation, list, validation, update, and HTML display")
else:
    expected = json.loads(expected_path.read_text())
    assert request("GET", todos) == [expected]
    assert b"<s>Updated todo</s>" in request("GET", "/")
    item = f'{todos}/{expected["id"]}'
    assert request("DELETE", item, 204) == b""
    assert request("GET", todos) == []
    assert request("DELETE", item, 404) == {"detail": "Todo not found"}
    print("Verified SQLite persistence across restart, delete, and missing-item 404")
