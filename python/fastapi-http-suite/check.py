from contextlib import closing
import http.client
import json
import sys
from urllib.parse import urlsplit


def read_json(connection, path, status):
    connection.request("GET", path)
    response = connection.getresponse()
    body = response.read()
    assert response.status == status, (path, response.status, body)
    assert response.headers.get_content_type() == "application/json", response.headers
    print(f"{status} {path}")
    return json.loads(body)


endpoint = urlsplit(sys.argv[1])
with closing(http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=5)) as client:
    assert read_json(client, "/", 200) == {"message": "Hello World"}
    schema = read_json(client, "/openapi.json", 200)
    assert schema["openapi"].startswith("3.")
    assert schema["info"]["title"] == "FastAPI"
    assert "200" in schema["paths"]["/"]["get"]["responses"]
    assert read_json(client, "/missing", 404) == {"detail": "Not Found"}
    assert read_json(client, "/", 200) == {"message": "Hello World"}
