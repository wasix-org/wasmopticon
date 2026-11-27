import json
import os
from contextlib import asynccontextmanager
from threading import Event, Thread

from fastapi import FastAPI, Request
from pydantic import BaseModel, Field
from redis import Redis

JOBS = "wasmopticon:jobs"
COMPLETED_IDS = "wasmopticon:completed-ids"
RESULTS = "wasmopticon:results"

COMPLETE_JOB = """
if redis.call('SADD', KEYS[1], ARGV[1]) == 1 then
    redis.call('RPUSH', KEYS[2], ARGV[2])
end
"""


class Job(BaseModel):
    id: str = Field(min_length=1, max_length=64)
    value: str = Field(min_length=1, max_length=128)


def redis_client():
    return Redis(
        host=os.environ["DB_HOST"],
        port=int(os.environ["DB_PORT"]),
        decode_responses=True,
        socket_connect_timeout=4,
        socket_timeout=4,
    )


def worker(stop):
    with redis_client() as client:
        while not stop.is_set():
            item = client.blpop(JOBS, timeout=1)
            if item is None:
                continue
            job = Job.model_validate_json(item[1])
            result = json.dumps({"id": job.id, "result": job.value.upper()})
            client.eval(COMPLETE_JOB, 2, COMPLETED_IDS, RESULTS, job.id, result)


@asynccontextmanager
async def lifespan(app):
    with redis_client() as client:
        client.ping()
        app.state.redis = client
        stop = Event()
        background = Thread(target=worker, args=(stop,), daemon=True)
        background.start()
        try:
            yield
        finally:
            stop.set()
            background.join(timeout=5)


app = FastAPI(lifespan=lifespan)


@app.get("/")
async def root():
    return {"redis": "ready"}


@app.post("/jobs", status_code=202)
def queue_job(job: Job, request: Request):
    request.app.state.redis.rpush(JOBS, job.model_dump_json())
    return {"id": job.id}


@app.get("/results")
def results(request: Request):
    return [json.loads(result) for result in request.app.state.redis.lrange(RESULTS, 0, -1)]
