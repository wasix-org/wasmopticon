from contextlib import closing
import hashlib
import http.client
import io
import sys
from urllib.parse import urlsplit

BODY_BYTES = 20 * 1024 * 1024
CHUNK_BYTES = 64 * 1024

endpoint = urlsplit(sys.argv[1])
payload = hashlib.shake_256(b"wasmopticon fastapi large body").digest(BODY_BYTES)
expected_sha256 = hashlib.sha256(payload).hexdigest()

with closing(
    http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=20, blocksize=CHUNK_BYTES)
) as client:
    client.request(
        "POST",
        "/round-trip",
        body=io.BytesIO(payload),
        headers={"Content-Type": "application/octet-stream", "Content-Length": str(len(payload))},
    )
    response = client.getresponse()
    assert response.status == 200, (response.status, response.read(512))
    assert response.headers.get_content_type() == "application/octet-stream"
    assert response.headers["Content-Length"] == str(len(payload))
    assert response.headers["X-Body-SHA256"] == expected_sha256

    size = 0
    download = hashlib.sha256()
    try:
        while chunk := response.read1(CHUNK_BYTES):
            assert chunk == payload[size : size + len(chunk)], f"Byte mismatch at offset {size}"
            size += len(chunk)
            download.update(chunk)
    except TimeoutError as error:
        raise AssertionError(f"Download stalled after {size} of {len(payload)} bytes") from error
    assert size == len(payload), (size, len(payload))
    assert download.hexdigest() == expected_sha256
    print(f"Verified {size} upload and download bytes, SHA-256 {expected_sha256}")
