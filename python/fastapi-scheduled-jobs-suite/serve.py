import os

from uvicorn import Config, Server

from src.main import app

if __name__ == "__main__":
    server = Server(
        Config(
            app,
            host=os.environ["HOST"],
            port=int(os.environ["PORT"]),
            loop="asyncio",
            http="h11",
            ws="none",
        )
    )
    app.state.server = server
    server.run()
