import os

import uvicorn

from main import app


if __name__ == "__main__":
    uvicorn.run(
        app,
        host=os.environ.get("HOST", "127.0.0.1"),
        port=int(os.environ.get("PORT", "8080")),
        loop="asyncio",
        http="h11",
        ws="none",
    )
