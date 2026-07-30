from __future__ import annotations

import json
import logging
from threading import Event, Thread
import time

from flask import Flask, jsonify, request

from .config import Settings
from .db import Job, Queue
from .github import GitHubClient, GitHubError, verify_signature
from .review import ReviewError, render_comment, run_review

LOG = logging.getLogger("review-sentinel")
READ_PERMISSIONS = {"contents": "read", "pull_requests": "read", "metadata": "read"}
WRITE_PERMISSIONS = {"pull_requests": "read", "issues": "write", "metadata": "read"}


def _repo_allowed(settings: Settings, repo: str) -> bool:
    return repo.lower() in settings.allowed_repositories


def _public_allowed(settings: Settings, repo: str) -> bool:
    return repo.lower() in settings.approved_public_repositories


def _publish(settings: Settings, queue: Queue, github: GitHubClient, job: Job) -> None:
    if not job.report:
        queue.complete(job.id, "failed", error="no structured report is available")
        return
    read_token = github.installation_token(job.installation_id, READ_PERMISSIONS)
    context = github.pull_request(read_token, job.repo, job.pull_number)
    if context.head_sha != job.head_sha or context.state != "open":
        queue.complete(job.id, "failed", error="pull request head changed or is no longer open")
        return
    if not context.private and not _public_allowed(settings, job.repo):
        queue.complete(job.id, "failed", error="public repository is not approved for Review Sentinel publication")
        return
    write_token = github.installation_token(job.installation_id, WRITE_PERMISSIONS)
    github.comment(write_token, job.repo, job.pull_number, render_comment(context, job.report, candidate=False))
    queue.complete(job.id, "published", job.report)


def _review(settings: Settings, queue: Queue, github: GitHubClient, job: Job) -> None:
    read_token = github.installation_token(job.installation_id, READ_PERMISSIONS)
    context = github.pull_request(read_token, job.repo, job.pull_number)
    if context.head_sha != job.head_sha:
        queue.complete(job.id, "failed", error="pull request head changed before review")
        return
    if context.state != "open" or context.draft:
        queue.complete(job.id, "failed", error="draft or closed pull request")
        return
    if not context.private and not _public_allowed(settings, job.repo):
        queue.complete(job.id, "failed", error="public repository is not approved for Review Sentinel")
        return
    report = run_review(settings, github, read_token, context, settings.schema_file)
    if context.private and settings.auto_publish_private:
        queue.complete(job.id, "candidate", report)
        fresh = queue.get(job.id)
        _publish(settings, queue, github, fresh)
        return
    queue.complete(job.id, "candidate", report)
    fresh = queue.get(job.id)
    if fresh.publish_requested:
        _publish(settings, queue, github, fresh)


def process_once(settings: Settings, queue: Queue, github: GitHubClient) -> bool:
    job = queue.claim_publication()
    if job is None:
        job = queue.claim()
    if job is None:
        return False
    try:
        if job.status == "publishing":
            _publish(settings, queue, github, job)
        else:
            _review(settings, queue, github, job)
    except (GitHubError, ReviewError, OSError, ValueError) as exc:
        LOG.exception("review job %s failed", job.id)
        queue.complete(job.id, "failed", error=str(exc)[:2000])
    return True


def worker_loop(settings: Settings, queue: Queue, github: GitHubClient, stop: Event) -> None:
    while not stop.is_set():
        if not process_once(settings, queue, github):
            stop.wait(2)


def create_app(settings: Settings, queue: Queue) -> Flask:
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = 2 * 1024 * 1024

    @app.get("/healthz")
    def healthz():
        return jsonify({"ok": True, "queue": queue.counts()})

    @app.post("/webhook")
    def webhook():
        raw = request.get_data(cache=True)
        if not verify_signature(raw, request.headers.get("X-Hub-Signature-256", ""), settings.webhook_secret):
            return jsonify({"error": "invalid signature"}), 401
        if request.headers.get("X-GitHub-Event") != "pull_request":
            return jsonify({"accepted": False, "reason": "event ignored"})
        payload = request.get_json(silent=True) or {}
        if payload.get("action") != "labeled":
            return jsonify({"accepted": False, "reason": "action ignored"})
        sender = payload.get("sender", {})
        if sender.get("type") == "Bot":
            return jsonify({"accepted": False, "reason": "bot event ignored"})
        repo = payload.get("repository", {}).get("full_name", "").lower()
        pull = payload.get("pull_request", {})
        number = int(pull.get("number") or payload.get("number") or 0)
        head_sha = pull.get("head", {}).get("sha", "")
        installation_id = int(payload.get("installation", {}).get("id") or 0)
        label = payload.get("label", {}).get("name", "")
        if not repo or not number or not head_sha or not installation_id or not _repo_allowed(settings, repo):
            return jsonify({"accepted": False, "reason": "repository or payload not allowed"}), 202
        if label == settings.publish_label:
            job = queue.request_publish(repo, number, head_sha)
            return jsonify({"accepted": bool(job), "job_id": job.id if job else None, "action": "publish"})
        if label != settings.trigger_label:
            return jsonify({"accepted": False, "reason": "label ignored"})
        try:
            job = queue.enqueue(repo, number, head_sha, installation_id)
        except RuntimeError as exc:
            return jsonify({"accepted": False, "error": str(exc)}), 429
        return jsonify({"accepted": True, "job_id": job.id, "status": job.status}), 202

    return app


def serve(settings: Settings) -> None:
    errors = settings.validate_runtime()
    if errors:
        raise RuntimeError("; ".join(errors))
    settings.data_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    queue = Queue(settings.data_dir / "review-sentinel.sqlite3", settings.max_queue)
    github = GitHubClient(settings.api_url, settings.app_id, settings.private_key_file)
    stop = Event()
    worker = Thread(target=worker_loop, args=(settings, queue, github, stop), daemon=True)
    worker.start()
    try:
        create_app(settings, queue).run(settings.bind_host, settings.bind_port, threaded=True, use_reloader=False)
    finally:
        stop.set()
        worker.join(timeout=5)
