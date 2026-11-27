import json
import socket
import sqlite3
import sys
import time
from contextlib import closing
from http.client import HTTPConnection
from pathlib import Path
from urllib.parse import urlsplit

database = Path(sys.argv[1])
address = urlsplit(sys.argv[2])


def request(method, path, status):
    client = HTTPConnection(address.hostname, address.port, timeout=2)
    try:
        client.request(method, path)
        response = client.getresponse()
        body = response.read()
        assert response.status == status, (path, response.status, body[:300])
        return json.loads(body)
    finally:
        client.close()


def host_state():
    with closing(sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True)) as db:
        rows = db.execute("SELECT id, at FROM ticks ORDER BY id").fetchall()
        markers = db.execute("SELECT stopped_at FROM lifecycle").fetchall()
    return rows, markers


deadline = time.monotonic() + 12
while True:
    rows = request("GET", "/", 200)["ticks"]
    if len(rows) >= 3:
        break
    assert time.monotonic() < deadline, f"only received {len(rows)} scheduled jobs"
    time.sleep(0.2)

gaps = [second[1] - first[1] for first, second in zip(rows, rows[1:])]
assert [row[0] for row in rows] == list(range(1, len(rows) + 1)), rows
assert all(0.5 <= gap <= 3.5 for gap in gaps), gaps

assert request("POST", "/shutdown", 202) == {"stopping": True}
deadline = time.monotonic() + 8
while True:
    try:
        with socket.create_connection((address.hostname, address.port), timeout=0.25):
            pass
    except ConnectionRefusedError:
        break
    assert time.monotonic() < deadline, "server remained listening after shutdown"
    time.sleep(0.1)

# The lifespan marker is committed only after the worker thread has joined.
deadline = time.monotonic() + 3
while True:
    stopped_rows, markers = host_state()
    if markers:
        break
    assert time.monotonic() < deadline, "worker did not record a joined shutdown"
    time.sleep(0.1)
assert [list(row) for row in stopped_rows[: len(rows)]] == rows
assert len(markers) == 1 and markers[0][0] >= stopped_rows[-1][1]
time.sleep(1.25)
assert host_state() == (stopped_rows, markers), "SQLite changed after shutdown"
print(f"Verified {len(rows)} ticks, gaps={gaps}, and no additional ticks after shutdown", flush=True)
