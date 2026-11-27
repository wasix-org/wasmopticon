import hashlib

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import Response

MAX_BODY_BYTES = 20 * 1024 * 1024
app = FastAPI()


@app.get("/")
async def ready():
    return {"ready": True}


@app.post("/round-trip")
async def round_trip(request: Request):
    body = bytearray()
    digest = hashlib.sha256()
    async for chunk in request.stream():
        if len(body) + len(chunk) > MAX_BODY_BYTES:
            raise HTTPException(413, "Body exceeds 20 MiB")
        body.extend(chunk)
        digest.update(chunk)
    return Response(
        bytes(body),
        media_type="application/octet-stream",
        headers={
            "Content-Length": str(len(body)),
            "X-Body-SHA256": digest.hexdigest(),
        },
    )
