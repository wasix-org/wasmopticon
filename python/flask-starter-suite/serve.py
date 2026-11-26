import os

from src.main import app


if __name__ == "__main__":
    app.run(host=os.environ["HOST"], port=int(os.environ["PORT"]), threaded=False)
