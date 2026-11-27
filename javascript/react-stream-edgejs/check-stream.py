import http.client
import re
import socket
import sys


SHELL = b"<h1>React stream shell</h1>"
FALLBACK = b'<p id="fallback">Waiting for release</p>'
DEFERRED = b'<p id="deferred">React deferred content</p>'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def read_line(source):
    data = source.readline(8192)
    require(data.endswith(b"\r\n"), f"Invalid or incomplete HTTP line: {data!r}")
    return data[:-2]


def read_chunks(source):
    while True:
        size = read_line(source).split(b";", 1)[0]
        require(re.fullmatch(rb"[0-9a-fA-F]+", size), f"Invalid chunk size: {size!r}")
        count = int(size, 16)
        if count == 0:
            require(read_line(source) == b"", "Unexpected chunk trailer")
            return
        require(count <= 64 * 1024, f"Unexpectedly large chunk: {count}")
        chunk = source.read(count)
        require(len(chunk) == count and source.read(2) == b"\r\n", "Incomplete HTTP chunk")
        yield chunk


def request(port, method, path):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    try:
        connection.request(method, path)
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


def check(port):
    with socket.create_connection(("127.0.0.1", port), timeout=10) as connection:
        connection.sendall(
            f"GET /stream HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n".encode()
        )
        with connection.makefile("rb") as source:
            status = read_line(source)
            require(status.split()[:2] == [b"HTTP/1.1", b"200"], f"Unexpected status: {status!r}")
            headers = http.client.parse_headers(source)
            require(headers.get_content_type() == "text/html", "Expected an HTML response")
            require(headers.get("Transfer-Encoding", "").lower() == "chunked", "Expected HTTP chunking")
            require("Content-Length" not in headers, "Expected a response without Content-Length")

            chunks = read_chunks(source)
            before_release = b""
            for chunk in chunks:
                before_release += chunk
                require(len(before_release) <= 64 * 1024, "Unexpectedly large React shell")
                require(DEFERRED not in before_release, "React sent deferred content before release")
                if SHELL in before_release and FALLBACK in before_release:
                    break
            else:
                raise AssertionError("Stream ended before sending the shell and fallback")

            print("PASS received the React shell and Suspense fallback before releasing content", flush=True)
            require(request(port, "POST", "/release") == (204, b""), "Release request failed")

            after_release = b"".join(chunks)
            require(DEFERRED in after_release, "React did not send the released content")
            require((before_release + after_release).endswith(b"</body></html>"), "Incomplete React HTML")
            print("PASS received deferred content and the final HTTP chunk", flush=True)

    require(request(port, "GET", "/") == (200, b"React streaming fixture ready"), "Server stopped responding")
    require(request(port, "POST", "/release") == (409, b""), "Completed stream left a pending gate")
    print("PASS server is healthy and the stream gate was cleared")


if __name__ == "__main__":
    check(int(sys.argv[1]))
