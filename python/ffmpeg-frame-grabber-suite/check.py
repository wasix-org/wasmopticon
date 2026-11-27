from http.client import HTTPConnection
import json
import struct
import sys
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])
width, height = 32, 24


def make_video():
    video = bytearray(f"YUV4MPEG2 W{width} H{height} F2:1 Ip A1:1 C420jpeg\n".encode())
    luma = width * height
    chroma = luma // 4
    for gray in (32, 96, 160, 220):
        video.extend(b"FRAME\n")
        video.extend(bytes([gray]) * luma + bytes([128]) * (2 * chroma))
    return bytes(video)


def upload(seconds, video, expected_status):
    boundary = "suite-ffmpeg-frame-grabber"
    body = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="file"; filename="sample.y4m"\r\n'
        "Content-Type: application/octet-stream\r\n\r\n"
    ).encode() + video + f"\r\n--{boundary}--\r\n".encode()
    connection = HTTPConnection(url.hostname, url.port, timeout=20)
    try:
        connection.request(
            "POST",
            f"/api/frame?time={seconds}",
            body,
            {"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        response = connection.getresponse()
        data = response.read()
        assert response.status == expected_status, (seconds, response.status, data[:400])
        return response.headers.get_content_type(), data
    finally:
        connection.close()


def check_jpeg(mime, frame):
    assert mime == "image/jpeg"
    assert frame.startswith(b"\xff\xd8") and frame.endswith(b"\xff\xd9")
    start_of_frame = frame.index(b"\xff\xc0")
    assert struct.unpack_from(">HH", frame, start_of_frame + 5) == (height, width)


video = make_video()
first_mime, first = upload(0, video, 200)
last_mime, last = upload(1.5, video, 200)
check_jpeg(first_mime, first)
check_jpeg(last_mime, last)
assert first != last, "Seeking should return a different video frame"

mime, invalid_time = upload(2, video, 422)
assert mime == "application/json"
assert "Pick a time below that" in json.loads(invalid_time)["detail"]

mime, invalid_video = upload(0, b"not video data", 415)
assert mime == "application/json"
assert "could not read that file as a video" in json.loads(invalid_video)["detail"]
print("Verified two distinct 32×24 JPEG frames, out-of-range seek, and malformed video")
