import os
import sqlite3
import time
from contextlib import asynccontextmanager, closing
from threading import Event, Thread

from fastapi import FastAPI

DB_PATH = os.environ.get("JOB_DB_PATH", "/tmp/interval-jobs.db")


def run_jobs(stop):
    with closing(sqlite3.connect(DB_PATH)) as db:
        while not stop.wait(1):
            with db:
                db.execute("INSERT INTO ticks (at) VALUES (?)", (time.monotonic(),))


@asynccontextmanager
async def lifespan(_):
    with closing(sqlite3.connect(DB_PATH)) as db, db:
        db.execute("CREATE TABLE ticks (id INTEGER PRIMARY KEY, at REAL NOT NULL)")
        db.execute("CREATE TABLE lifecycle (stopped_at REAL NOT NULL)")
    stop = Event()
    worker = Thread(target=run_jobs, args=(stop,), name="interval-jobs", daemon=True)
    worker.start()
    try:
        yield
    finally:
        stop.set()
        worker.join(timeout=5)
        if worker.is_alive():
            raise RuntimeError("interval job thread missed its shutdown deadline")
        with closing(sqlite3.connect(DB_PATH)) as db, db:
            db.execute("INSERT INTO lifecycle VALUES (?)", (time.monotonic(),))


app = FastAPI(lifespan=lifespan)


@app.get("/")
async def ticks():
    with closing(sqlite3.connect(DB_PATH)) as db:
        return {"ticks": db.execute("SELECT id, at FROM ticks ORDER BY id").fetchall()}


@app.post("/shutdown", status_code=202)
async def shutdown():
    app.state.server.should_exit = True
    return {"stopping": True}
