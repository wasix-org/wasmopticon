import json
import struct
import sys
import zlib
from http.client import HTTPConnection
from urllib.parse import urlparse

url = urlparse(sys.argv[1])


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def sample_png():
    header = struct.pack(">IIBBBBB", 400, 200, 8, 2, 0, 0, 0)
    rows = (b"\0" + b"\xda\x42\x23" * 400) * 200
    return b"\x89PNG\r\n\x1a\n" + b"".join(
        [png_chunk(b"IHDR", header), png_chunk(b"IDAT", zlib.compress(rows)), png_chunk(b"IEND", b"")]
    )


def jpeg_size(image):
    assert image.startswith(b"\xff\xd8") and image.endswith(b"\xff\xd9")
    offset = 2
    while image[offset : offset + 1] == b"\xff":
        marker = image[offset + 1]
        length = struct.unpack_from(">H", image, offset + 2)[0]
        if marker in (0xC0, 0xC2):
            height, width, channels = struct.unpack_from(">HHB", image, offset + 5)
            assert channels == 3
            return width, height
        assert length >= 2 and marker != 0xDA
        offset += length + 2
    raise AssertionError("No JPEG frame header")


def upload(image, expected_status):
    fields = {"rotate": "90", "crop": "0,0,200,300", "width": "100", "format": "jpeg"}
    boundary = b"wasmopticon-image"
    parts = [
        f'Content-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
        for name, value in fields.items()
    ]
    parts.append(
        b'Content-Disposition: form-data; name="file"; filename="sample.png"\r\n'
        b"Content-Type: image/png\r\n\r\n" + image + b"\r\n"
    )
    payload = b"".join(b"--" + boundary + b"\r\n" + part for part in parts) + b"--" + boundary + b"--\r\n"
    client = HTTPConnection(url.hostname, url.port, timeout=15)
    try:
        client.request("POST", "/api/edit", payload, {"Content-Type": f"multipart/form-data; boundary={boundary.decode()}"})
        response = client.getresponse()
        data = response.read()
        assert response.status == expected_status, (response.status, data[:300])
        return response.headers, data
    finally:
        client.close()


headers, image = upload(sample_png(), 200)
assert headers.get_content_type() == "image/jpeg"
assert (headers["X-Image-Width"], headers["X-Image-Height"]) == ("100", "150")
assert jpeg_size(image) == (100, 150)
_, error = upload(b"not a PNG", 415)
assert "image" in json.loads(error)["detail"].lower()
print("Verified PNG upload, rotate/crop/resize, 100×150 RGB JPEG output, and invalid image rejection")
