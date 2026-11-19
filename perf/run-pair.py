#!/usr/bin/env python3
"""Run one serial pair on Linux with per-role systemd scope telemetry."""

import argparse
from datetime import datetime, timezone
import errno
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import socket
import subprocess
import time
import urllib.parse
import urllib.request
import uuid

CGROUP = Path("/sys/fs/cgroup")
CGROUP_FILES = (
    "cpu.stat", "cpu.max", "cpu.pressure", "memory.current", "memory.peak",
    "memory.max", "memory.events", "memory.swap.current", "memory.pressure",
    "io.stat", "io.pressure", "pids.current",
)
BUILD_TOOLS = {"rustc", "mbx-rustc", "cc1", "cc1plus", "clang", "gcc",
               "ld.lld", "turbopack", "esbuild", "rolldown", "wasm-opt"}
RUST_BUILD_ACTIONS = {"build", "check", "test", "clippy", "run", "rustc", "bench"}
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
SAMPLE_SECONDS = 2


def read(path):
    try:
        return path.read_text().strip()
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return None


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def checksums(path, expected):
    digest = sha256(path)
    if digest != expected:
        raise RuntimeError(f"{path} has SHA-256 {digest}; expected {expected}")


def active_builds():
    builds = []
    for proc in Path("/proc").glob("[0-9]*"):
        name = read(proc / "comm")
        action = None
        if name in ("cargo", "mbx", "anybuild"):
            argv = (read(proc / "cmdline") or "").split("\0")
            build_actions = {"build"} if name == "anybuild" else RUST_BUILD_ACTIONS
            action = next((arg for arg in argv[1:] if arg in build_actions), None)
        if action or name in BUILD_TOOLS or (name or "").startswith(("npm ", "next-build")):
            stat = read(proc / "stat")
            if stat and stat.rsplit(")", 1)[1].split()[0] != "Z":
                builds.append(f"{proc.name}:{name}" + (f":{action}" if action else ""))
    return builds


def cgroup_stats(group):
    return {name: read(group / name) for name in CGROUP_FILES}


def group_for_pid(pid):
    membership = read(Path(f"/proc/{pid}/cgroup"))
    if membership:
        return CGROUP / membership.split("::", 1)[1].lstrip("/")
    return None


def sample_group(group):
    processes = {}
    for pid in (read(group / "cgroup.procs") or "").split():
        proc = Path("/proc") / pid
        status = read(proc / "status") or ""
        fields = ("Name:", "VmRSS:", "VmHWM:", "Threads:", "Cpus_allowed_list:")
        try:
            fds = len(list((proc / "fd").iterdir()))
        except (FileNotFoundError, PermissionError):
            fds = None
        processes[pid] = {"status": [s for s in status.splitlines() if s.startswith(fields)],
                          "fds": fds}
    return {"cgroup": cgroup_stats(group), "processes": processes}


class Role:
    def __init__(self, path, name, command, env, cpus, cwd):
        self.name = f"wasix-perf-{uuid.uuid4().hex[:12]}-{name}.scope"
        pidfile = path / f"{name}.pid"
        timed = ["/usr/bin/time", "-v", "-o", str(path / f"{name}.time"), *command]
        wrapped = ["bash", "-c", 'echo "$$" > "$1"; shift; exec "$@"', "role", str(pidfile),
                   "taskset", "-c", cpus, *timed]
        argv = ["systemd-run", "--user", "--scope", "--quiet", f"--unit={self.name}",
                "-p", "CPUAccounting=yes", "-p", "MemoryAccounting=yes", *wrapped]
        with (path / "commands.log").open("a") as log:
            print(shlex.join([f"{key}={value}" for key, value in env.items()] + argv), file=log)
        with (path / f"{name}.log").open("w") as log:
            self.process = subprocess.Popen(argv, env=os.environ | env, cwd=cwd,
                                            stdout=log, stderr=subprocess.STDOUT,
                                            start_new_session=True)
        self.group = None
        self.db_group = None
        try:
            for _ in range(100):
                pid = read(pidfile)
                self.group = group_for_pid(pid) if pid else None
                if self.group is not None:
                    return
                if self.process.poll() is not None:
                    break
                time.sleep(0.05)
            raise RuntimeError(f"no cgroup for {name}; check {name}.log")
        except (Exception, KeyboardInterrupt):
            self.stop()
            raise

    def stop(self):
        if self.process.poll() is None or (self.group and self.group.exists()):
            subprocess.run(["systemctl", "--user", "stop", self.name],
                           timeout=25, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if self.process.poll() is None:
            self.process.terminate()
        self.process.wait(timeout=10)


def observe(out, stage, server, min_available_gib, client=None):
    builds = active_builds()
    row = {
        "epoch": time.time(), "mono": time.monotonic(), "stage": stage, "builds": builds,
        "host_cpu": read(Path("/proc/stat")).split("intr", 1)[0].strip(),
        "host_memory": dict(re.findall(r"^(MemAvailable|SwapFree):\s+(\d+)",
                                       read(Path("/proc/meminfo")), re.MULTILINE)),
        "host_pressure": {r: read(Path("/proc/pressure") / r) for r in ("cpu", "memory", "io")},
        "server": sample_group(server.group),
        "scope_parent_cpu_stat": read(server.group.parent / "cpu.stat"),
        "scope_parent_cpu_max": read(server.group.parent / "cpu.max"),
        "user_slice_memory_max": read(CGROUP / "user.slice" / "memory.max"),
    }
    if client:
        row["client"] = sample_group(client.group)
    if server.db_group is not None:
        row["db"] = sample_group(server.db_group)
        if not row["db"]["processes"]:
            raise RuntimeError(f"DB scope is empty during {stage}")
    with out.open("a") as stream:
        print(json.dumps(row), file=stream)
    if builds:
        raise RuntimeError(f"concurrent build detected during {stage}: {', '.join(builds)}")
    available_gib = int(row["host_memory"]["MemAvailable"]) / 2**20
    if available_gib < min_available_gib:
        raise RuntimeError(f"host memory reserve fell to {available_gib:.2f} GiB during {stage}")
    if server.process.poll() is not None:
        raise RuntimeError(f"server exited during {stage}; check server.log")


def probe(target, ready_path, ready_body):
    try:
        with HTTP.open(target + ready_path, timeout=1.5) as response:
            return response.status == 200 and ready_body.encode() in response.read()
    except OSError:
        return False


def load(args, out, name, seconds, rate, server, client_env):
    phase = {"name": name, "duration": seconds, "maxVusers": args.max_vusers}
    if rate == int(rate):
        phase["arrivalRate"] = int(rate)
    else:
        arrivals = round(seconds * rate)
        if arrivals < 1:
            raise RuntimeError(f"{name}: fractional rate yields no arrivals")
        phase["arrivalCount"] = arrivals
    overrides = json.dumps({"config": {"phases": [phase]}}, separators=(",", ":"))
    argv = [str(args.artillery), "run", "--platform", "local", "--target", args.artillery_target,
            "--overrides", overrides, "--output", str(out / f"{name}.json"), str(args.scenario)]
    client = Role(out, name, argv, client_env, args.client_cpus, args.cwd)
    deadline = time.monotonic() + seconds + 90
    try:
        while True:
            observe(out / "telemetry.jsonl", name, server, args.min_available_gib, client)
            try:
                status = client.process.wait(timeout=SAMPLE_SECONDS)
            except subprocess.TimeoutExpired:
                if time.monotonic() > deadline:
                    raise RuntimeError(f"client timed out during {name}")
                continue
            (out / f"{name}.exit").write_text(f"{status}\n")
            if not (out / f"{name}.json").is_file():
                raise RuntimeError(f"Artillery exited {status} without a report during {name}")
            return
    finally:
        client.stop()


def wait_for_port(port):
    deadline = time.monotonic() + 70
    while True:
        with socket.socket() as sock:
            sock.settimeout(0.3)
            endpoint = ("127.0.0.1", port)
            if sock.connect_ex(endpoint) == 0:
                raise RuntimeError(f"another listener is using loopback port {port}")
        with socket.socket() as sock:
            try:
                sock.bind(endpoint)
                return
            except OSError as err:
                if err.errno != errno.EADDRINUSE or time.monotonic() > deadline:
                    raise
        time.sleep(0.5)


def fixture_command(fixture, out, args, lane, binary, env):
    checksums(fixture["path"], fixture["sha256"])
    env.update(fixture.get("env", {}))
    env.update(WASMER_BIN=binary, WASIX_LANE=lane, PORT=str(args.port))
    env[fixture["package_env"]] = args.package
    env[fixture["db_receipt_env"]] = str(out / "db-container-name")
    image = subprocess.check_output(
        ["docker", "image", "inspect", "--format", "{{.Id}} {{.Architecture}}", fixture["db_image"]],
        text=True, timeout=15,
    )
    (out / "db-image.log").write_text(image)
    ready = out / "fixture-ready"
    done = out / "fixture-done"
    # The fixture owns service setup and cleanup. Its callback keeps the ready service alive.
    hook = ('set -eu; name=$3; printf "%s\n" "${!name}" >"$1.tmp"; '
            'mv "$1.tmp" "$1"; until [[ -e "$2" ]]; do sleep 1; done')
    return [fixture["path"], "bash", "-c", hook, "fixture", str(ready), str(done),
            fixture["db_container_env"]]


def identify_db(container, out, expected_cpus):
    fields = "{{.State.Pid}} {{.Id}} {{.Image}} {{.HostConfig.CpusetCpus}}"
    metadata = subprocess.check_output(["docker", "inspect", "--format", fields, container],
                                       text=True, timeout=15).strip()
    endpoint = subprocess.check_output(["docker", "port", container], text=True, timeout=15)
    pid, _, _, cpus = metadata.split()
    group = group_for_pid(int(pid))
    (out / "db-container.log").write_text(f"{container} {metadata}\n{endpoint}{group}\n")
    if cpus != expected_cpus or not re.fullmatch(r"3306/tcp -> 127\.0\.0\.1:[0-9]+", endpoint.strip()):
        raise RuntimeError(f"unexpected DB affinity or publish mapping for {container}")
    if group is None:
        raise RuntimeError(f"missing cgroup for DB container {container}")
    return group


def verify_connection_reuse(out, target, paths):
    command = ["curl", "--noproxy", "*", "--fail", "--silent", "--show-error",
               "--max-time", "3", "--write-out", "%{num_connects}\n"]
    for path in paths:
        if not path.startswith("/") or path.startswith("//"):
            raise RuntimeError("connection reuse paths must be relative to the loopback target")
        command.extend(["--output", "/dev/null", target + path])
    result = subprocess.check_output(command, text=True, timeout=10).splitlines()
    (out / "connection-reuse.log").write_text(shlex.join(command) + "\n" + "\n".join(result) + "\n")
    if result != ["1"] + ["0"] * (len(paths) - 1):
        raise RuntimeError("expected the same HTTP connection for all readiness probe requests")


def observe_idle(samples, name, seconds, server, min_available_gib):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        observe(samples, name, server, min_available_gib)
        time.sleep(min(SAMPLE_SECONDS, max(0, deadline - time.monotonic())))


def run_lane(args, lane, binary, launch, fixture=None):
    out = args.out / lane
    out.mkdir()
    wait_for_port(args.port)
    checksums(args.scenario, args.scenario_sha256)
    checksums(args.package, args.sha256)
    env = {"WASMER_DIR": str(args.out / "state" / lane),
           "WASMER_CACHE_DIR": str(args.cache / lane), "NO_PROXY": "127.0.0.1,localhost"}
    client_env = {"ARTILLERY_DISABLE_TELEMETRY": "1", "ARTILLERY_DISABLE_UPDATE_CHECK": "true",
                  "NO_PROXY": "127.0.0.1,localhost", "HTTP_PROXY": "", "HTTPS_PROXY": "",
                  "ALL_PROXY": "", "http_proxy": "", "https_proxy": "", "all_proxy": ""}
    if fixture:
        command = fixture_command(fixture, out, args, lane, binary, env)
    else:
        if args.package not in launch:
            raise RuntimeError(f"{lane}: launch does not reference pinned WebC {args.package}")
        command = [binary, *launch]
    started = time.monotonic()
    samples = out / "telemetry.jsonl"
    server = None
    try:
        server = Role(out, "server", command, env, args.server_cpus, args.cwd)
        while True:
            container = read(out / "fixture-ready") if fixture else None
            if (not fixture or container) and probe(args.target, args.ready_path, args.ready_body):
                break
            observe(samples, "startup", server, args.min_available_gib)
            if time.monotonic() - started > args.ready_seconds:
                raise RuntimeError(f"{lane}: readiness deadline; check server.log")
            time.sleep(0.5)
        if container:
            server.db_group = identify_db(container, out, fixture["db_cpus"])
        (out / "ready-seconds").write_text(f"{time.monotonic() - started:.3f}\n")
        observe(samples, "ready", server, args.min_available_gib)
        if paths := getattr(args, "reuse_paths", []):
            verify_connection_reuse(out, args.target, paths)
        if args.preload_idle_seconds:
            observe_idle(samples, "baseline-idle", args.preload_idle_seconds,
                         server, args.min_available_gib)
        if args.mode == "smoke":
            steps = [("validate", 6, 3)]
        elif args.mode == "sweep":
            steps = [("smoke", 30, 1), ("warm", 60, args.rates[0])]
            steps += [(f"load-{rate:g}", 60, rate) for rate in args.rates]
        else:
            steps = [("warm", 60, args.rates[0]), ("soak", args.soak_seconds, args.rates[0])]
        for name, seconds, rate in steps:
            load(args, out, name, seconds, rate, server, client_env)
        if args.mode == "soak":
            observe_idle(samples, "idle", args.idle_seconds, server, args.min_available_gib)
        observe(samples, "final", server, args.min_available_gib)
        if not probe(args.target, args.ready_path, args.ready_body):
            raise RuntimeError(f"{lane}: final readiness probe failed")
        if fixture:
            (out / "fixture-done").touch()
            if server.process.wait(timeout=60):
                raise RuntimeError(f"{lane}: fixture post-load check failed; check server.log")
        checksums(args.package, args.sha256)
        checksums(args.scenario, args.scenario_sha256)
    finally:
        try:
            if server is not None:
                server.stop()
        finally:
            container = read(out / "db-container-name") if fixture else None
            if container:
                names = subprocess.check_output(
                    ["docker", "ps", "-a", "--filter", f"name=^/{re.escape(container)}$",
                     "--format", "{{.Names}}"],
                    timeout=15, text=True,
                ).splitlines()
                if container in names:
                    subprocess.run(["docker", "rm", "--force", "--volumes", container],
                                   check=True, timeout=25, stdout=subprocess.DEVNULL)
                    raise RuntimeError(f"{lane}: fixture left DB container {container}")
                (out / "db-cleanup.log").write_text(f"Confirmed absent: {container}\n")
    print(f"{lane} complete at {datetime.now(timezone.utc).isoformat()}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path, help="JSON with artifact, scenario, readiness and lane argv")
    parser.add_argument("mode", choices=("smoke", "sweep", "soak"))
    parser.add_argument("out", type=Path)
    parser.add_argument("--rates", type=float, nargs="+", required=True)
    parser.add_argument("--wait-lock", action="store_true")
    parser.add_argument("--lane", choices=("v1", "v2"), help="single diagnostic lane")
    parser.add_argument("--reverse", action="store_true")
    parser.add_argument("--soak-seconds", type=int, default=1800)
    parser.add_argument("--idle-seconds", type=int, default=300)
    parser.add_argument("--preload-idle-seconds", type=int, default=0)
    parser.add_argument("--min-available-gib", type=float, default=0)
    parser.add_argument("--ready-seconds", type=int, default=90)
    parser.add_argument("--max-vusers", type=int, default=100)
    args = parser.parse_args()
    args.__dict__.update(json.loads(args.spec.read_text()))
    args.out = args.out.resolve()
    args.cache = Path(args.cache).resolve()
    args.artillery = Path(args.artillery).resolve()
    args.scenario = Path(args.scenario).resolve()
    args.target = f"http://127.0.0.1:{args.port}"
    args.artillery_target = getattr(args, "artillery_target", args.target)
    target = urllib.parse.urlsplit(args.artillery_target)
    if (target.scheme not in ("http", "ws") or target.hostname != "127.0.0.1"
            or target.port != args.port or target.username or target.password):
        parser.error("Artillery target must use the same loopback port")
    if not 1024 <= args.port <= 65535 or not all(math.isfinite(rate) and rate > 0 for rate in args.rates):
        parser.error("require a nonprivileged loopback port and positive rates")
    if not args.ready_path.startswith("/") or args.ready_path.startswith("//"):
        parser.error("readiness path must be on the loopback target")
    source = Path(__file__).read_bytes()
    lock = Path(f"/tmp/wasix-expansion-perf-{os.getuid()}.lock")
    with lock.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX if args.wait_lock else fcntl.LOCK_EX | fcntl.LOCK_NB)
        if builds := active_builds():
            raise RuntimeError(f"concurrent builds before run: {', '.join(builds)}")
        args.out.mkdir(parents=True)
        (args.out / "spec.json").write_text(args.spec.read_text())
        for dependency in getattr(args, "dependencies", []):
            checksums(dependency["path"], dependency["sha256"])
        args.scenario_sha256 = sha256(args.scenario)
        shutil.copyfile(args.scenario, args.out / ("scenario" + args.scenario.suffix))
        (args.out / "runner.py").write_bytes(source)
        context = {
            "started": datetime.now(timezone.utc).isoformat(),
            "artillery": subprocess.check_output([args.artillery, "--version"],
                                                 env=os.environ | {"ARTILLERY_DISABLE_TELEMETRY": "1"},
                                                 text=True).strip(),
            "scenario_sha256": args.scenario_sha256, "runner_sha256": hashlib.sha256(source).hexdigest(),
            "host": subprocess.check_output(["lscpu"], text=True),
            "settings": vars(args),
            "binaries": {name: {"sha256": sha256(lane["binary"]),
                                "version": subprocess.check_output([lane["binary"], "--version", "-v"],
                                                                   text=True).strip()}
                         for name, lane in args.lanes.items()},
        }
        (args.out / "context.json").write_text(json.dumps(context, indent=2, default=str) + "\n")
        lanes = ("v2", "v1") if args.reverse else ("v1", "v2")
        for lane in ((args.lane,) if args.lane else lanes):
            run_lane(args, lane, **args.lanes[lane])
            for dependency in getattr(args, "dependencies", []):
                checksums(dependency["path"], dependency["sha256"])


if __name__ == "__main__":
    # Let normal termination unwind managed scopes and the host lock.
    signal.signal(signal.SIGTERM, signal.default_int_handler)
    main()
