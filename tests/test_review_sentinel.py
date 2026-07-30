from __future__ import annotations

import hashlib
import hmac
import io
import json
import os
from pathlib import Path
import tempfile
import tarfile
import unittest
from unittest.mock import patch

from review_sentinel.db import Queue
from review_sentinel.config import Settings
from review_sentinel.github import verify_signature
from review_sentinel.review import render_comment, validate_report
from review_sentinel.review import ReviewError, _extract_archive
from review_sentinel.github import PullRequestContext
from review_sentinel.service import create_app


class ReviewSentinelTests(unittest.TestCase):
    def test_runtime_rejects_interactive_codex_home_and_requires_explicit_binary(self) -> None:
        with tempfile.NamedTemporaryFile() as key:
            with patch.dict(os.environ, {
                "REVIEW_SENTINEL_APP_ID": "123",
                "REVIEW_SENTINEL_PRIVATE_KEY_FILE": key.name,
                "REVIEW_SENTINEL_WEBHOOK_SECRET": "secret",
                "REVIEW_SENTINEL_ALLOWED_REPOSITORIES": "owner/repo",
                "REVIEW_SENTINEL_CODEX_BIN": "/bin/true",
                "REVIEW_SENTINEL_CODEX_HOME": "/home/claude/.codex",
            }, clear=False):
                errors = Settings.from_env().validate_runtime()
        self.assertTrue(any("dedicated review-only Codex home" in error for error in errors))

    def test_signature_requires_sha256_prefix_and_matches_constant_time(self) -> None:
        payload = b'{"action":"labeled"}'
        secret = "test-secret"
        digest = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
        self.assertTrue(verify_signature(payload, f"sha256={digest}", secret))
        self.assertFalse(verify_signature(payload, digest, secret))
        self.assertFalse(verify_signature(payload + b"x", f"sha256={digest}", secret))

    def test_queue_deduplicates_exact_head_and_tracks_publication_request(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            queue = Queue(Path(raw) / "queue.sqlite3", max_queue=2)
            first = queue.enqueue("owner/repo", 7, "a" * 40, 42)
            duplicate = queue.enqueue("owner/repo", 7, "a" * 40, 42)
            self.assertEqual(first.id, duplicate.id)
            self.assertEqual(queue.enqueue("owner/repo", 7, "b" * 40, 42).status, "queued")
            with self.assertRaises(RuntimeError):
                queue.enqueue("owner/repo", 8, "c" * 40, 42)
            claimed = queue.claim()
            assert claimed is not None
            report = {"verdict": "no_findings", "summary": "clean", "findings": []}
            queue.complete(claimed.id, "candidate", report)
            requested = queue.request_publish("owner/repo", 7, "a" * 40)
            assert requested is not None
            self.assertTrue(requested.publish_requested)
            publication = queue.claim_publication()
            assert publication is not None
            self.assertEqual(publication.id, claimed.id)

    def test_report_validation_and_marker_comment(self) -> None:
        report = {
            "verdict": "findings",
            "summary": "A real issue.",
            "findings": [{"severity": "high", "title": "Bad input", "body": "Validate it.", "file": "src/a.py", "line": 12}],
        }
        validate_report(report, "a" * 40)
        context = PullRequestContext("owner/repo", 7, "a" * 40, "b" * 40, "https://github.com/owner/repo/pull/7", True, False, "open")
        comment = render_comment(context, report, candidate=False)
        self.assertIn("<!-- review-sentinel-report -->", comment)
        self.assertIn("src/a.py:12", comment)
        self.assertIn("CI/Ruleset", comment)

    def test_invalid_report_is_rejected(self) -> None:
        with self.assertRaises(Exception):
            validate_report({"verdict": "findings", "summary": "x", "findings": [{"severity": "critical"}]}, "a" * 40)

    def test_archive_expansion_limit_is_enforced(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            archive = Path(raw) / "repo.tar.gz"
            target = Path(raw) / "repo"
            with tarfile.open(archive, "w:gz") as tar:
                payload = b"0123456789"
                info = tarfile.TarInfo("repo/file.txt")
                info.size = len(payload)
                tar.addfile(info, io.BytesIO(payload))
            with self.assertRaises(ReviewError):
                _extract_archive(archive, target, max_bytes=5)

    def test_signed_webhook_payload_is_parsed_after_signature_verification(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            with patch.dict(os.environ, {
                "REVIEW_SENTINEL_DATA_DIR": raw,
                "REVIEW_SENTINEL_WEBHOOK_SECRET": "secret",
                "REVIEW_SENTINEL_ALLOWED_REPOSITORIES": "owner/repo",
            }, clear=False):
                settings = Settings.from_env()
                queue = Queue(Path(raw) / "queue.sqlite3")
                app = create_app(settings, queue)
                payload = json.dumps({
                    "action": "labeled",
                    "repository": {"full_name": "owner/repo"},
                    "pull_request": {
                        "number": 7,
                        "head": {"sha": "a" * 40},
                    },
                    "installation": {"id": 42},
                    "label": {"name": "review-sentinel"},
                    "sender": {"type": "User"},
                }).encode()
                signature = hmac.new(b"secret", payload, hashlib.sha256).hexdigest()
                response = app.test_client().post("/webhook", data=payload, headers={
                    "X-Hub-Signature-256": f"sha256={signature}",
                    "X-GitHub-Event": "pull_request",
                    "Content-Type": "application/json",
                })
        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.json["accepted"], True)


if __name__ == "__main__":
    unittest.main()
