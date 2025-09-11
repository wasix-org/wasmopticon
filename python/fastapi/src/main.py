import os

from fastapi import FastAPI

app = FastAPI(
    title="FastAPI test app",
    description="A very simple test app to ensure that fastAPI is deployable",
    version="0.1.0",
)


@app.get("/")
async def root():
    return {
        "message": "FastAPI test app",
        "version": "0.1.0",
        "endpoints": [
            "/",
        ],
    }


@app.get("/health")
async def health_check():
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn

    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host=host, port=port)
