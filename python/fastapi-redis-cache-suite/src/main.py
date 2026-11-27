import os
from typing import Annotated

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from redis import Redis

cache = Redis(
    host=os.environ["REDIS_HOST"],
    port=int(os.environ["REDIS_PORT"]),
    decode_responses=True,
    socket_connect_timeout=3,
    socket_timeout=3,
)

app = FastAPI()


class CacheValue(BaseModel):
    value: str


@app.get("/")
def ready():
    return {"ready": cache.ping()}


@app.put("/cache/{key}")
def set_value(key: str, data: CacheValue):
    cache.set(key, data.value)
    return {"key": key, "value": data.value}


@app.get("/cache/{key}")
def get_value(key: str):
    value = cache.get(key)
    if value is None:
        raise HTTPException(404, "Cache miss")
    return {"key": key, "value": value}


@app.post("/cache/{key}/expire")
def expire(key: str, seconds: Annotated[int, Query(ge=1)]):
    if not cache.expire(key, seconds):
        raise HTTPException(404, "Cache miss")
    return {"key": key, "expires_in": seconds}
