#!/usr/bin/env python3
"""
Snapshot templates from git repositories defined in a TOML file.

Reads an adjacent TOML file `tracked-repos.toml` with entries:

  [[repositories]]
  name = "..."
  giturl = "git@github.com:org/repo.git"
  store_path = "python"           # category/folder
  git_ref = "main"                # branch, tag, or commit hash
  description = "Longer free-text description"

Behavior:
  - For each entry, fetch whatever the `git_ref` currently points to (branch,
    tag, or explicit commit), determine the resolved commit hash, and create a
    shallow snapshot under `<ROOT>/<store_path>/<name>/<commit-hash>`.
  - The snapshot directory contains a marker file with the commit hash. If a
    snapshot for that commit already exists, it is skipped. This allows
    re-running to append new snapshots for moving refs (e.g., branches) while
    keeping previous versions intact.
  - No automatic pruning is performed. Old snapshots remain until manually
    removed.

Only uses the Python standard library (uses `tomllib` for TOML). Requires the
`git` CLI to be available. Python 3.11+ recommended (3.13 supported).
"""

from __future__ import annotations

import argparse
import logging
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Tuple

MARKER_FILENAME = ".managed-by-snapshot-templates"

REQUIRED_FIELDS = ("name", "giturl", "store_path", "git_ref", "description")


@dataclass
class RepoSpec:
    name: str
    giturl: str
    store_path: str
    git_ref: str
    description: str

    @classmethod
    def from_row(cls, row: dict) -> "RepoSpec":
        missing_base = [c for c in REQUIRED_FIELDS if c not in row]
        if missing_base:
            raise ValueError(
                f"Config missing required fields: {', '.join(missing_base)}"
            )
        return cls(
            name=(row.get("name") or "").strip(),
            giturl=(row.get("giturl") or "").strip(),
            store_path=(row.get("store_path") or "").strip(),
            git_ref=(row.get("git_ref") or "").strip(),
            description=(row.get("description") or "").strip(),
        )


def configure_logging(verbose: bool) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname).1s %(message)s",
        datefmt="%H:%M:%S",
    )


def sanitize_for_path(value: str) -> str:
    """Return a filesystem-safe name: letters, digits, dot, dash, underscore.

    Any other character is replaced with an underscore. Collapses repeats.
    """
    value = value.strip()
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", value)
    value = re.sub(r"_+", "_", value)
    return value.strip("._-") or "item"


def ensure_git_available() -> None:
    if shutil.which("git") is None:
        logging.error("git CLI not found in PATH. Please install git.")
        raise SystemExit(2)


def run_git(args: List[str], cwd: Path, timeout: int = 300) -> Tuple[int, str, str]:
    cmd = ["git", "-c", "advice.detachedHead=false", *args]
    logging.debug("$ (cd %s && %s)", cwd, " ".join(cmd))
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )
    if proc.returncode != 0:
        logging.debug("git stdout: %s", proc.stdout.strip())
        logging.debug("git stderr: %s", proc.stderr.strip())
    return proc.returncode, proc.stdout, proc.stderr


def clone_at_ref_shallow(
    giturl: str, ref: str, target_dir: Path, timeout: int = 600
) -> None:
    """Clone a shallow snapshot of `giturl` at `ref` into `target_dir`.

    Uses `git init` + `git fetch --depth 1 origin <ref>` + checkout.
    Initializes submodules if present (best-effort). Raises RuntimeError on error.
    """
    # Create the target dir if not exists
    target_dir.mkdir(parents=True, exist_ok=True)

    # Initialize empty repo
    code, _, err = run_git(["init"], cwd=target_dir)
    if code != 0:
        raise RuntimeError(f"git init failed: {err.strip()}")

    # Add origin
    code, _, err = run_git(["remote", "add", "origin", giturl], cwd=target_dir)
    if code != 0:
        raise RuntimeError(f"git remote add failed: {err.strip()}")

    # Fetch ref shallowly (works for branch, tag, or commit reachable from remote)
    code, _, err = run_git(
        ["fetch", "--depth", "1", "origin", ref], cwd=target_dir, timeout=timeout
    )
    if code != 0:
        # Fallback: fetch full ref if shallow fetch unsupported
        logging.warning(
            "Shallow fetch failed for ref %s; falling back to full fetch.", ref
        )
        code, _, err = run_git(
            ["fetch", "origin", ref], cwd=target_dir, timeout=timeout
        )
        if code != 0:
            raise RuntimeError(f"git fetch ref failed: {err.strip()}")

    # Checkout fetched commit (detached HEAD)
    code, _, err = run_git(["checkout", "--detach", "FETCH_HEAD"], cwd=target_dir)
    if code != 0:
        raise RuntimeError(f"git checkout failed: {err.strip()}")

    # Do not initialize submodules; we snapshot only top-level tracked files
    # (explicitly avoid creating nested repos or fetching submodule contents)
    pass


def git_rev_parse_head(repo_dir: Path) -> str:
    code, out, err = run_git(["rev-parse", "HEAD"], cwd=repo_dir)
    if code != 0:
        raise RuntimeError(f"git rev-parse HEAD failed: {err.strip()}")
    return out.strip()


def export_tracked_files(src_repo_dir: Path, dest_dir: Path) -> None:
    """Export only tracked files from a checkout into dest_dir (no .git).

    Uses `git ls-files -z` to enumerate tracked files and copies them preserving
    metadata. Creates parent directories as needed.
    """
    code, out, err = run_git(["ls-files", "-z"], cwd=src_repo_dir)
    if code != 0:
        raise RuntimeError(f"git ls-files failed: {err.strip()}")
    files = [p for p in out.split("\x00") if p]
    dest_dir.mkdir(parents=True, exist_ok=True)
    for rel in files:
        src_path = src_repo_dir / rel
        dst_path = dest_dir / rel
        dst_path.parent.mkdir(parents=True, exist_ok=True)
        # Copy files; directories will be created as needed
        shutil.copy2(src_path, dst_path)


def write_marker_with_hash(target_dir: Path, commit_hash: str) -> None:
    """Write a sentinel file containing the resolved commit hash."""
    marker_path = target_dir / MARKER_FILENAME
    try:
        marker_path.write_text(f"{commit_hash}\n", encoding="utf-8")
    except Exception:
        logging.debug("Could not write marker file: %s", marker_path)


def existing_commit_hashes_for_repo(base_dir: Path) -> List[str]:
    """Read marker files under base_dir and collect commit hashes."""
    hashes: List[str] = []
    if not base_dir.exists():
        return hashes
    for marker in base_dir.rglob(MARKER_FILENAME):
        try:
            txt = marker.read_text(encoding="utf-8").strip()
        except Exception:
            continue
        if re.fullmatch(r"[0-9a-fA-F]{40}", txt):
            hashes.append(txt.lower())
    return hashes


def read_toml_specs(toml_path: Path) -> List[RepoSpec]:
    try:
        import tomllib  # Python 3.11+
    except ModuleNotFoundError:  # pragma: no cover - environment guard
        logging.error("tomllib not available; Python 3.11+ is required for TOML config")
        raise

    data: dict
    with toml_path.open("rb") as f:
        data = tomllib.load(f)
    repos = data.get("repositories")
    if not isinstance(repos, list):
        raise ValueError("TOML must define an array 'repositories' of tables")
    specs: List[RepoSpec] = []
    for i, item in enumerate(repos, start=1):
        if not isinstance(item, dict):
            logging.error("TOML entry %d invalid (not a table)", i)
            continue
        try:
            specs.append(RepoSpec.from_row(item))
        except Exception as e:
            logging.error("TOML entry %d invalid: %s", i, e)
    return specs


def process_repo(
    spec: RepoSpec, root_dir: Path, timeout: int
) -> Tuple[bool, Optional[str]]:
    if not spec.giturl or not spec.git_ref or not spec.name or not spec.store_path:
        return (
            False,
            "missing required fields (name, giturl, store_path, git_ref)",
        )

    safe_category = sanitize_for_path(spec.store_path)
    safe_name = sanitize_for_path(spec.name)
    base_dir = root_dir / safe_category / safe_name

    # Ensure base directory exists before scanning/creating temp dirs
    base_dir.mkdir(parents=True, exist_ok=True)

    # Collect existing commit hashes for this repo
    existing_hashes = set(existing_commit_hashes_for_repo(base_dir))

    # Work in a temporary directory under the base_dir so moves are cheap
    temp_dir = Path(tempfile.mkdtemp(prefix=f".tmp-{safe_name}-", dir=str(base_dir)))
    created_dir = True
    try:
        logging.info("Fetching %s ref %s to resolve commit...", spec.name, spec.git_ref)
        clone_at_ref_shallow(spec.giturl, spec.git_ref, temp_dir, timeout=timeout)
        commit_hash = git_rev_parse_head(temp_dir).lower()

        if commit_hash in existing_hashes:
            logging.info(
                "Skip %s (commit %s already snapped)", spec.name, commit_hash[:12]
            )
            try:
                shutil.rmtree(temp_dir)
            except Exception:
                pass
            return True, None

        target_dir = base_dir / commit_hash
        if target_dir.exists():
            logging.info(
                "Skip %s (dir for commit %s already exists)",
                spec.name,
                commit_hash[:12],
            )
            try:
                shutil.rmtree(temp_dir)
            except Exception:
                pass
            return True, None

        logging.info(
            "Snapshot %s@%s -> %s",
            spec.name,
            commit_hash[:12],
            target_dir,
        )
        # Export only tracked files to target and write marker
        export_tracked_files(temp_dir, target_dir)
        write_marker_with_hash(target_dir, commit_hash)
        return True, None
    except Exception as e:
        try:
            if created_dir and temp_dir.exists():
                shutil.rmtree(temp_dir)
        except Exception:
            logging.debug("Could not remove temporary directory: %s", temp_dir)
        return False, str(e)


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Clone repository snapshots at a given ref from a TOML config.",
    )
    parser.add_argument(
        "--config",
        dest="config_path",
        type=Path,
        default=Path(__file__).with_name("tracked-repos.toml"),
        help=(
            "Path to TOML config. If omitted, looks for tracked-repos.toml "
            "next to the script."
        ),
    )
    parser.add_argument(
        "--root",
        dest="root",
        type=Path,
        default=Path(__file__).parent,
        help="Root output directory to store snapshots (default: script directory)",
    )
    parser.add_argument(
        "--timeout",
        dest="timeout",
        type=int,
        default=600,
        help="Per-repository network timeout in seconds (default: 600)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable debug logging",
    )
    return parser.parse_args(list(argv) if argv is not None else None)


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = parse_args(argv)
    configure_logging(args.verbose)
    ensure_git_available()

    root_dir: Path = args.root

    # Resolve config path: use TOML
    config_path: Optional[Path] = args.config_path
    if not config_path or not config_path.exists():
        logging.error("Config file not found: %s", config_path)
        return 2

    # Load specs based on extension (TOML only)
    try:
        if config_path.suffix.lower() == ".toml":
            specs = read_toml_specs(config_path)
        else:
            logging.error(
                "Unsupported config extension: %s (expected .toml)", config_path.suffix
            )
            return 2
    except Exception as e:
        logging.error("Failed to read config: %s", e)
        return 2

    if not specs:
        logging.warning("No repository entries found in config: %s", config_path)
        return 0

    successes = 0
    failures: List[Tuple[RepoSpec, str]] = []

    for spec in specs:
        ok, err = process_repo(spec, root_dir=root_dir, timeout=args.timeout)
        if ok:
            successes += 1
        else:
            failures.append((spec, err or "unknown error"))
            logging.error(
                "Failed %s@%s: %s", spec.name or spec.giturl, spec.git_ref, err
            )

    logging.info("Done: %d succeeded, %d failed", successes, len(failures))
    if failures:
        for spec, err in failures:
            logging.debug("Failure detail: %s@%s -> %s", spec.name, spec.git_ref, err)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
