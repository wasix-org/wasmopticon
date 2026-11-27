import os

import pypandoc
import uvicorn

os.environ["PYPANDOC_PANDOC"] = "/app/pandoc"

from src.main import app


if __name__ == "__main__":
    # Compile and verify the guest converter within the startup deadline.
    pypandoc.get_pandoc_version()
    uvicorn.run(
        app,
        host=os.environ.get("HOST", "127.0.0.1"),
        port=int(os.environ.get("PORT", "8080")),
        loop="asyncio",
        http="h11",
        ws="none",
    )
