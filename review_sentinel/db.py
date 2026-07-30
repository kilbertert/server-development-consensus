from __future__ import annotations

from dataclasses import dataclass
from contextlib import contextmanager
import json
from pathlib import Path
import sqlite3
import time


@dataclass(frozen=True)
class Job:
    id: int
    repo: str
    pull_number: int
    head_sha: str
    installation_id: int
    status: str
    attempts: int
    publish_requested: bool
    report: dict | None


class Queue:
    def __init__(self, path: Path, max_queue: int = 20) -> None:
        self.path = path
        self.max_queue = max_queue
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self._init()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=30)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA busy_timeout=30000")
        return connection

    @contextmanager
    def _db(self):
        connection = self._connect()
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def _init(self) -> None:
        with self._db() as db:
            db.executescript("""
              CREATE TABLE IF NOT EXISTS jobs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                repo TEXT NOT NULL,
                pull_number INTEGER NOT NULL,
                head_sha TEXT NOT NULL,
                installation_id INTEGER NOT NULL,
                status TEXT NOT NULL,
                attempts INTEGER NOT NULL DEFAULT 0,
                publish_requested INTEGER NOT NULL DEFAULT 0,
                report_json TEXT,
                error TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                UNIQUE(repo, pull_number, head_sha)
              );
              CREATE INDEX IF NOT EXISTS jobs_status_idx ON jobs(status, created_at);
            """)
            columns = {row["name"] for row in db.execute("PRAGMA table_info(jobs)")}
            if "publish_requested" not in columns:
                db.execute("ALTER TABLE jobs ADD COLUMN publish_requested INTEGER NOT NULL DEFAULT 0")

    @staticmethod
    def _job(row: sqlite3.Row) -> Job:
        return Job(
            id=row["id"], repo=row["repo"], pull_number=row["pull_number"],
            head_sha=row["head_sha"], installation_id=row["installation_id"],
            status=row["status"], attempts=row["attempts"],
            publish_requested=bool(row["publish_requested"]),
            report=json.loads(row["report_json"]) if row["report_json"] else None,
        )

    def enqueue(self, repo: str, pull_number: int, head_sha: str, installation_id: int) -> Job:
        now = time.time()
        with self._db() as db:
            row = db.execute(
                "SELECT * FROM jobs WHERE repo=? AND pull_number=? AND head_sha=?",
                (repo, pull_number, head_sha),
            ).fetchone()
            if row:
                return self._job(row)
            pending = db.execute("SELECT count(*) FROM jobs WHERE status IN ('queued','running')").fetchone()[0]
            if pending >= self.max_queue:
                raise RuntimeError("review queue capacity reached")
            cursor = db.execute(
                "INSERT INTO jobs(repo,pull_number,head_sha,installation_id,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",
                (repo, pull_number, head_sha, installation_id, "queued", now, now),
            )
            row = db.execute("SELECT * FROM jobs WHERE id=?", (cursor.lastrowid,)).fetchone()
            return self._job(row)

    def get(self, job_id: int) -> Job:
        with self._db() as db:
            row = db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        if not row:
            raise KeyError(job_id)
        return self._job(row)

    def claim(self) -> Job | None:
        with self._db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM jobs WHERE status='queued' ORDER BY created_at LIMIT 1").fetchone()
            if not row:
                return None
            now = time.time()
            db.execute("UPDATE jobs SET status='running', attempts=attempts+1, updated_at=? WHERE id=?", (now, row["id"]))
            row = db.execute("SELECT * FROM jobs WHERE id=?", (row["id"],)).fetchone()
        return self._job(row)

    def request_publish(self, repo: str, pull_number: int, head_sha: str) -> Job | None:
        with self._db() as db:
            db.execute(
                "UPDATE jobs SET publish_requested=1, updated_at=? WHERE repo=? AND pull_number=? AND head_sha=? AND status IN ('candidate','running','queued')",
                (time.time(), repo, pull_number, head_sha),
            )
            row = db.execute(
                "SELECT * FROM jobs WHERE repo=? AND pull_number=? AND head_sha=?",
                (repo, pull_number, head_sha),
            ).fetchone()
        return self._job(row) if row else None

    def claim_publication(self) -> Job | None:
        with self._db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM jobs WHERE status='candidate' AND publish_requested=1 ORDER BY updated_at LIMIT 1").fetchone()
            if not row:
                return None
            db.execute("UPDATE jobs SET status='publishing', updated_at=? WHERE id=?", (time.time(), row["id"]))
            row = db.execute("SELECT * FROM jobs WHERE id=?", (row["id"],)).fetchone()
        return self._job(row)

    def complete(self, job_id: int, status: str, report: dict | None = None, error: str | None = None) -> None:
        if status not in {"completed", "failed", "candidate", "published"}:
            raise ValueError(status)
        with self._db() as db:
            db.execute(
                "UPDATE jobs SET status=?, report_json=?, error=?, updated_at=? WHERE id=?",
                (status, json.dumps(report) if report else None, error, time.time(), job_id),
            )

    def counts(self) -> dict[str, int]:
        with self._db() as db:
            rows = db.execute("SELECT status, count(*) AS count FROM jobs GROUP BY status").fetchall()
        return {row["status"]: row["count"] for row in rows}
