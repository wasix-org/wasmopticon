#!/usr/bin/env python3
"""Run wasmopticon's fixture checks with one frozen package per fixture."""

import argparse
import hashlib
import json
import os
import shlex
import shutil
import socket
import subprocess
import time
import tomllib
from concurrent.futures import ThreadPoolExecutor
from fnmatch import fnmatchcase
from pathlib import Path
from threading import Lock

ROOT = Path(__file__).resolve().parent
PACKAGE = ".anybuild/suite/package.webc"


def discover():
    for directory, children, files in os.walk(ROOT):
        children[:] = sorted(d for d in children if not d.startswith(".") and d != "node_modules")
        if {"build.sh", "test.sh"} <= set(files):
            rel = Path(directory).relative_to(ROOT).as_posix()
            yield rel


def cases(name, config):
    for variant in config.get("variants", [None]):
        for profile, env in config.get("profiles", {None: {}}).items():
            label = ":".join(part for part in (name, variant, profile) if part)
            package = f".suite/{variant}/{PACKAGE}" if variant else config.get("package", PACKAGE)
            yield label, package, [variant] if variant else [], env


def positive(value):
    result = int(value)
    if result < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return result


def args_for_cli():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--v1", help="released WASIX v1 Wasmer binary")
    parser.add_argument("--v2", help="WASIX v2 Wasmer binary with C API support")
    parser.add_argument("--filter", action="append", default=[], help="fixture substring or glob; repeat to include more")
    parser.add_argument("--jobs", type=positive, default=1, help="fixtures to run concurrently (default 1)")
    parser.add_argument("--build", action="store_true", help="build every selected package with the first lane's binary")
    parser.add_argument("--retry-on-timeout", type=int, default=1, metavar="N", help="extra attempts after a test timeout (default 1)")
    parser.add_argument("--registry-dir", default=os.environ.get("REGISTRY_DIR"), type=Path, help="offline registry for Edge.js fixtures")
    parser.add_argument("--output", type=Path, default=Path(".suite/results"), help="report and log directory")
    parser.add_argument("--cache-dir", type=Path, help="parent of separate v1-cranelift and v2-cranelift caches")
    parser.add_argument("--list", action="store_true", help="list selected fixture cases without running")
    args = parser.parse_args()
    if args.retry_on_timeout < 0:
        parser.error("--retry-on-timeout must be nonnegative")
    lanes = {}
    for lane in ("v1", "v2"):
        binary = getattr(args, lane)
        if binary:
            path = shutil.which(binary)
            if path is None:
                parser.error(f"{lane} binary not executable: {binary}")
            lanes[lane] = str(Path(path).resolve())
    if not args.list and not lanes:
        parser.error("provide --v1, --v2, or both")
    return args, lanes


class Ports:
    def __init__(self):
        self.used = set()
        self.lock = Lock()

    def allocate(self):
        with self.lock:
            while True:
                with socket.socket() as listener:
                    listener.bind(("127.0.0.1", 0))
                    port = listener.getsockname()[1]
                if port not in self.used:
                    self.used.add(port)
                    return str(port)


def docker_access(output):
    available = set()
    docker = shutil.which("docker")
    sudo = shutil.which("sudo")
    fallback = None
    if not docker:
        return available, fallback
    for mode, command in (("direct", [docker]), ("sudo", [sudo, "-n", docker] if sudo else [])):
        if command and subprocess.run(
            ["timeout", "-k", "2", "8", *command, "info"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ).returncode == 0:
            available.add(mode)
    if "sudo" in available and "direct" not in available:
        fallback = output / "docker-sudo"
        fallback.mkdir(exist_ok=True)
        wrapper = fallback / "docker"
        wrapper.write_text(f'#!/bin/sh\nexec {shlex.quote(sudo)} -n {shlex.quote(docker)} "$@"\n')
        wrapper.chmod(0o700)
        available.add("direct")
    return available, fallback


def sha256(path):
    if path.is_file():
        with path.open("rb") as handle:
            return hashlib.file_digest(handle, "sha256").hexdigest()
    return None


def run_script(directory, script, arguments, env, seconds, log, output):
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    with log.open("w") as handle:
        try:
            code = subprocess.run(
                ["timeout", "--kill-after=30", str(seconds), str(directory / script), *arguments],
                cwd=directory, env=env, stdout=handle, stderr=subprocess.STDOUT,
            ).returncode
        except OSError as error:
            print(error, file=handle)
            code = 126
    return {
        "exit_code": code,
        "duration_s": round(time.monotonic() - started, 3),
        "log": str(log.relative_to(output)),
        "status": "pass" if code == 0 else "timeout" if code in (124, 137) else "fail",
    }


def case_result(reason, lanes, row, status):
    row["lanes"] = {
        lane: {"status": status, "duration_s": None, "reason": reason} for lane in lanes
    }
    return row


def run_fixture(name, config, selected, args, lanes, ports, output, docker, docker_wrapper):
    directory = ROOT / name
    built = {}
    results = []
    for label, package_path, script_args, profile_env in selected:
        package = directory / package_path
        row = {"fixture": label, "webc_sha256": sha256(package), "lanes": {}}
        results.append(row)
        docker_mode = config.get("docker")
        reason = config.get("skip")
        if docker_mode and docker_mode not in docker:
            reason = f"Docker unavailable for {docker_mode} execution"
        if reason:
            case_result(reason, lanes, row, "skip")
            continue

        work = output / "logs" / label.replace(":", "/")
        env = {**os.environ, **profile_env}
        # Python's support scripts need their own registry, prepared by build.sh.
        env.pop("REGISTRY_DIR", None)
        if args.registry_dir and name.startswith("javascript/"):
            env["REGISTRY_DIR"] = str(args.registry_dir.resolve())
        if docker_mode == "direct" and docker_wrapper:
            env["PATH"] = f"{docker_wrapper}{os.pathsep}{env.get('PATH', os.defpath)}"
        if args.build:
            if package not in built:
                build_env = {
                    **env,
                    "WASMER_BIN": next(iter(lanes.values())),
                    "WASMER_DIR": str(work / "build-state"),
                    "WASMER_CACHE_DIR": str(output / "cache" / "build"),
                }
                built[package] = run_script(
                    directory, "build.sh", script_args, build_env, config.get("build_timeout", 600),
                    work / "build.log", output,
                )
            row["build"] = built[package]
            row["webc_sha256"] = sha256(package)
            if row["build"]["status"] != "pass":
                case_result("build did not complete successfully", lanes, row, "fail")
                continue
        if not row["webc_sha256"]:
            case_result(f"missing {package_path}; run with --build", lanes, row, "fail")
            continue
        if package_env := config.get("package_env"):
            env[package_env] = str(package)

        for lane, binary in lanes.items():
            attempts = []
            for attempt in range(1, args.retry_on_timeout + 2):
                if sha256(package) != row["webc_sha256"]:
                    attempts.append({"status": "fail", "duration_s": 0, "reason": "WebC changed before test"})
                    break
                test_env = {
                    **env,
                    "WASMER_BIN": binary,
                    "WASIX_LANE": lane,
                    "WASMER_DIR": str(work / f"{lane}-{attempt}-state"),
                    "WASMER_CACHE_DIR": str((args.cache_dir or output / "cache").resolve() / f"{lane}-cranelift"),
                    "PORT": ports.allocate(),
                }
                if config.get("database_port"):
                    test_env["DB_PORT"] = ports.allocate()
                result = run_script(
                    directory, "test.sh", script_args, test_env, config.get("timeout", 180),
                    work / f"{lane}-{attempt}.log", output,
                )
                result["port"] = int(test_env["PORT"])
                if "DB_PORT" in test_env and config.get("database_port"):
                    result["database_port"] = int(test_env["DB_PORT"])
                attempts.append(result)
                if sha256(package) != row["webc_sha256"]:
                    result.update(status="fail", reason="WebC changed during test")
                if result["status"] != "timeout":
                    break
            row["lanes"][lane] = {
                **attempts[-1],
                "duration_s": round(sum(item["duration_s"] for item in attempts), 3),
                "attempts": attempts,
            }
        print(f"{label} " + " ".join(f"{lane}={value['status']}" for lane, value in row["lanes"].items()), flush=True)
    return results


def markdown(rows, lanes):
    def cell(result):
        duration = result["duration_s"]
        text = result["status"].upper()
        if duration is not None:
            text += f" ({duration:.3f}s)"
        if len(result.get("attempts", [])) > 1:
            text += f", {len(result['attempts'])} attempts"
        if reason := result.get("reason"):
            text += f" · {reason}"
        return text.replace("|", r"\|")

    lines = [
        "| Fixture | WebC SHA-256 | " + " | ".join(lanes) + " |",
        "| --- | --- | " + " | ".join("---" for _ in lanes) + " |",
    ]
    for row in rows:
        digest = row["webc_sha256"]
        values = [f'`{row["fixture"]}`', f'`{digest}`' if digest else "—"]
        values.extend(cell(row["lanes"][lane]) for lane in lanes)
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines) + "\n"


def main():
    args, lanes = args_for_cli()
    configs = tomllib.loads((ROOT / "wasix-suite.toml").read_text())["fixtures"]
    selected = {}
    for name in discover():
        config = configs.get(name, {})
        matches = [
            case for case in cases(name, config)
            if not args.filter or any(pattern in case[0] or fnmatchcase(case[0], pattern) for pattern in args.filter)
        ]
        if matches:
            selected[name] = matches
    if not selected:
        raise SystemExit("No fixtures matched")
    if args.list:
        for matches in selected.values():
            for label, *_ in matches:
                print(label)
        return 0

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    docker, docker_wrapper = docker_access(output) if any(configs.get(name, {}).get("docker") for name in selected) else (set(), None)
    ports = Ports()
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        jobs = [
            pool.submit(run_fixture, name, configs.get(name, {}), cases_, args, lanes, ports, output, docker, docker_wrapper)
            for name, cases_ in selected.items()
        ]
        results = [row for job in jobs for row in job.result()]
    (output / "results.json").write_text(json.dumps({
        "lanes": {lane: {"binary": binary, "sha256": sha256(Path(binary))} for lane, binary in lanes.items()},
        "results": results,
    }, indent=2) + "\n")
    (output / "results.md").write_text(markdown(results, lanes))
    print(f"Reports: {output / 'results.md'} and {output / 'results.json'}")
    return int(any(
        lane["status"] in ("fail", "timeout") for row in results for lane in row["lanes"].values()
    ))


if __name__ == "__main__":
    raise SystemExit(main())
