from __future__ import annotations

import argparse
import json
import logging
import os
from pathlib import Path

from .config import Settings
from .db import Queue
from .service import serve


def _load_env_file(path: Path) -> None:
    if not path.is_file():
        return
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def main() -> None:
    parser = argparse.ArgumentParser(prog="review-sentinel")
    parser.add_argument("--env-file", type=Path)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("doctor")
    subparsers.add_parser("serve")
    show = subparsers.add_parser("show")
    show.add_argument("job_id", type=int)
    args = parser.parse_args()
    if args.env_file:
        _load_env_file(args.env_file)
    settings = Settings.from_env()
    if args.command == "doctor":
        errors = settings.validate_runtime()
        queue = Queue(settings.data_dir / "review-sentinel.sqlite3", settings.max_queue)
        print(json.dumps({"ready": not errors, "errors": errors, "queue": queue.counts()}, sort_keys=True))
        raise SystemExit(0 if not errors else 2)
    if args.command == "show":
        queue = Queue(settings.data_dir / "review-sentinel.sqlite3", settings.max_queue)
        job = queue.get(args.job_id)
        print(json.dumps({
            "id": job.id,
            "repo": job.repo,
            "pull_number": job.pull_number,
            "head_sha": job.head_sha,
            "status": job.status,
            "attempts": job.attempts,
            "publish_requested": job.publish_requested,
            "report": job.report,
        }, sort_keys=True))
        return
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    serve(settings)


if __name__ == "__main__":
    main()
