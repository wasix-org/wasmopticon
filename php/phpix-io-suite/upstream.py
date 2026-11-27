import http.server
import json
import socket
import sys
from pathlib import Path


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/probe":
            self.send_error(404)
            return
        body = b"PHPix loopback upstream\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


path = Path(sys.argv[1])
http_port, timeout_port = map(int, sys.argv[2:])

with (
    http.server.HTTPServer(("127.0.0.1", http_port), Handler) as http,
    socket.socket() as blackhole,
):
    blackhole.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    blackhole.bind(("127.0.0.1", timeout_port))
    blackhole.listen(0)
    filled = []
    try:
        # Leave the accepted queue full, so new connections time out at connect.
        for _ in range(8):
            try:
                filled.append(socket.create_connection(blackhole.getsockname(), timeout=0.25))
            except TimeoutError:
                break
        else:
            raise RuntimeError("Could not saturate the local TCP listen backlog")

        pending = path.with_suffix(".tmp")
        pending.write_text(json.dumps({"http": http.server_port, "timeout": blackhole.getsockname()[1]}))
        pending.replace(path)
        http.serve_forever()
    finally:
        for connection in filled:
            connection.close()
