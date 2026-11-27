import os
import subprocess

import uvicorn

from main import app


if __name__ == "__main__":
    os.environ["PATH"] = "/app/bin:" + os.environ.get("PATH", "")
    # Compile and verify both guest tools within the startup deadline.
    for executable in ("ffprobe", "ffmpeg"):
        subprocess.run([f"/app/bin/{executable}", "-version"], check=True, capture_output=True)
    uvicorn.run(
        app,
        host=os.environ.get("HOST", "127.0.0.1"),
        port=int(os.environ.get("PORT", "8080")),
        loop="asyncio",
        http="h11",
        ws="none",
    )
