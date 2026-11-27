import json
import math
import os
import signal
import socket
import subprocess
import time
from http.client import HTTPConnection
from pathlib import Path
from tempfile import NamedTemporaryFile


def seconds(name, default):
    value = float(os.environ.get(name, default))
    if not math.isfinite(value) or value <= 0:
        raise ValueError(f"{name} must be a finite positive number")
    return value


def bind_port(port):
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", port))
        listener.listen()
        return listener.getsockname()[1]


def wait_until_ready(server, port, deadline):
    while server.poll() is None and time.monotonic() < deadline:
        client = HTTPConnection("127.0.0.1", port, timeout=0.75)
        try:
            client.request("GET", "/")
            response = client.getresponse()
            if response.status == 200 and json.loads(response.read()) == {"message": "Hello World"}:
                return
        except OSError:
            pass
        finally:
            client.close()
        time.sleep(0.1)
    raise RuntimeError(f"server missed readiness deadline or exited ({server.poll()})")


def stop_on_interrupt(signum, _):
    raise SystemExit(128 + signum)


def main():
    signal.signal(signal.SIGINT, stop_on_interrupt)
    signal.signal(signal.SIGTERM, stop_on_interrupt)
    ready_timeout = seconds("READY_TIMEOUT", "90")
    grace = seconds("SHUTDOWN_TIMEOUT", "10")
    requested_port = int(os.environ.get("PORT", "0"))
    port = bind_port(requested_port)
    logs = Path(".anybuild/suite")
    logs.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=logs, prefix="shutdown.", suffix=".log", delete=False) as log:
        print(f"Server log: {Path(log.name).resolve()}", flush=True)
        server = subprocess.Popen(
            ["./serve.sh"], env={**os.environ, "PORT": str(port)},
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        try:
            wait_until_ready(server, port, time.monotonic() + ready_timeout)
            print(f"Ready on 127.0.0.1:{port}, sending SIGTERM to PID {server.pid}", flush=True)
            started = time.monotonic()
            server.terminate()
            code = server.wait(timeout=grace)
            elapsed = time.monotonic() - started
            output = Path(log.name).read_text(errors="replace")
            lifespan = "Application shutdown complete." in output
            bind_port(port)
            print(
                f"SIGTERM exit={code} elapsed={elapsed:.3f}s "
                f"uvicorn_shutdown={lifespan} port_rebound=True",
                flush=True,
            )
            # Uvicorn may re-raise SIGTERM after completing its lifespan shutdown.
            assert code in (0, -signal.SIGTERM, 128 + signal.SIGTERM), f"unexpected exit {code}"
            assert lifespan, "SIGTERM exited before Uvicorn completed its lifespan shutdown"
        except (Exception, SystemExit):
            try:
                os.killpg(server.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            server.wait(timeout=5)
            print(Path(log.name).read_text(errors="replace"), end="", flush=True)
            raise


if __name__ == "__main__":
    main()
