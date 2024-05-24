import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from http import HTTPStatus
import urllib.request
import urllib.parse
from typing import List
import logging

class TestServer(BaseHTTPRequestHandler):
    def handle_one_request(self):
        try:
            self.raw_requestline = self.rfile.readline(65537)
            if len(self.raw_requestline) > 65536:
                self.requestline = ''
                self.request_version = ''
                self.command = ''
                self.send_error(HTTPStatus.REQUEST_URI_TOO_LONG)
                return
            if not self.raw_requestline:
                self.close_connection = True
                return
            if not self.parse_request():
                # An error code has been sent, just exit
                return

            try:
                self.handler()
            except Exception as e:
                self.send_response(HTTPStatus.INTERNAL_SERVER_ERROR)
                self.end_headers()
                self.wfile.write(f'exception occured during request processing: {e}'.encode())

            self.wfile.flush() #actually send the response if not already done.
        except TimeoutError as e:
            #a read or a write timed out.  Discard this connection
            self.log_error("Request timed out: %r", e)
            self.close_connection = True
            return

    def handler(self):

        # If path is a full URL, strip the domain part

        path = self.path
        if path.startswith('http://') or path.startswith('https://'):
            path = path.removeprefix('http://').removeprefix('https://')
            path = path[path.index('/'):]

        parts = path.lstrip('/').split('/')
        if len(parts) < 1:
            self.send_response(HTTPStatus.OK)
            self.end_headers()
            self.wfile.write(b'python testserver - use an available test route')
            return

        route = parts[0]
        if route == 'http-proxy':
            self.handler_http_proxy(parts[1:])
        else:
            # Unknown route
            self.send_response(HTTPStatus.NOT_FOUND)
            self.end_headers()
            self.wfile.write(f'route not found: "{route}"'.encode())

    def handler_http_proxy(self, parts: List[str]):
        target = '/'.join(parts)

        try:
            url = urllib.parse.urlparse(target)
        except Exception as e:
            self.send_response(HTTPStatus.BAD_REQUEST)
            self.end_headers()
            self.wfile.write(f'invalid URL "{target}": {e}'.encode())
            return

        headers = dict(self.headers)
        headers.pop('Host', None)
        headers.pop('host', None)

        data = {
            "url": target,
            "method": self.command,
            "headers": headers,
        }

        content_len = self.headers.get('Content-Length')
        request_body = None
        if content_len or self.command in ['POST', 'PUT', 'PATCH']:
            request_body = self.rfile.read()

        req =  urllib.request.Request(target, method=self.command, data=request_body, headers=headers)
        logging.info(f"proxying request | {data}")
        resp = urllib.request.urlopen(req)
        logging.info(f'received response | status={resp.status}')

        self.send_response(resp.status)
        for key, value in resp.getheaders():
            self.send_header(key, value)
        self.end_headers()

        out_body = resp.read()
        self.wfile.write(out_body)

def run():
    logging.basicConfig(level=logging.DEBUG)

    port = int(os.environ.get('PORT', default=8080))
    interface = os.environ.get('INTERFACE', default='0.0.0.0')

    logging.info(f"Starting server on http://{interface}:{port}")

    httpd = HTTPServer((interface, port), TestServer)
    httpd.serve_forever()

run()
