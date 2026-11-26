import json
import sys
from http.client import HTTPConnection
from urllib.parse import urlsplit


def request(origin, method, path, status, headers=None, body=None):
    url = urlsplit(origin)
    connection = HTTPConnection(url.hostname, url.port, timeout=5)
    try:
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        data = response.read()
        assert response.status == status, (method, path, response.status, data)
        if data and response.headers.get_content_type() == "application/json":
            return json.loads(data)
        return data
    finally:
        connection.close()


def main(origin):
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }

    def call(request_id, method, params=None):
        body = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params or {}}
        response = request(origin, "POST", "/mcp", 200, headers, json.dumps(body))
        assert response["jsonrpc"] == "2.0" and response["id"] == request_id, response
        return response["result"]

    page = request(origin, "GET", "/", 200)
    assert (origin + "/mcp").encode() in page and b"public sample data" in page

    protocol = "2025-06-18"
    initialized = call(
        1,
        "initialize",
        {
            "protocolVersion": protocol,
            "capabilities": {},
            "clientInfo": {"name": "wasmopticon", "version": "1"},
        },
    )
    assert initialized["protocolVersion"] == protocol, initialized
    assert initialized["serverInfo"]["name"] == "Cupcake orders", initialized
    assert "tools" in initialized["capabilities"], initialized
    headers["MCP-Protocol-Version"] = protocol
    notification = {"jsonrpc": "2.0", "method": "notifications/initialized"}
    assert request(origin, "POST", "/mcp", 202, headers, json.dumps(notification)) == b""

    tools = call(2, "tools/list")
    assert {tool["name"] for tool in tools["tools"]} == {"search", "fetch"}, tools
    search = call(3, "tools/call", {"name": "search", "arguments": {"query": "alice"}})
    assert not search.get("isError"), search
    citation = origin + "/records/1"
    assert search["structuredContent"]["results"] == [
        {"id": "1", "title": "Alice order", "url": citation}
    ], search
    assert json.loads(search["content"][0]["text"]) == search["structuredContent"], search

    fetched = call(4, "tools/call", {"name": "fetch", "arguments": {"id": "1"}})
    assert not fetched.get("isError"), fetched
    document = fetched["structuredContent"]
    assert document["url"] == citation and document["metadata"]["customer"] == "Alice", document
    assert json.loads(fetched["content"][0]["text"]) == document, fetched
    public_record = request(origin, "GET", "/records/1", 200)
    assert public_record == {key: value for key, value in document.items() if key != "url"}, public_record
    assert request(origin, "GET", "/records/unknown", 404) == {"error": "Order not found"}
    print("Verified MCP initialize, tools/list, search, fetch, and local citations")


if __name__ == "__main__":
    main(sys.argv[1])
