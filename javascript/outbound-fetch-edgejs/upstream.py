"""Host HTTP server for the outbound Edge.js fixture."""

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Upstream(BaseHTTPRequestHandler):
    def do_GET(self):
        print(f"GET {self.path}", flush=True)
        if self.path == "/slow":
            time.sleep(5)
        status, body = (404, {"error": "missing at upstream"}) if self.path == "/missing" else (
            200, {"source": "host-upstream", "probe": self.headers.get("X-Edgejs-Probe")}
        )
        payload = json.dumps(body).encode()
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError):
            # The timeout request intentionally disconnects before we respond.
            pass


with ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Upstream) as server:
    print(server.server_port, flush=True)
    server.serve_forever()
