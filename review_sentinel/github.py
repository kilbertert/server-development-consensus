from __future__ import annotations

import hashlib
import hmac
import json
from dataclasses import dataclass
from pathlib import Path
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import jwt


@dataclass(frozen=True)
class PullRequestContext:
    repo: str
    number: int
    head_sha: str
    base_sha: str
    html_url: str
    private: bool
    draft: bool
    state: str


class GitHubError(RuntimeError):
    pass


class GitHubClient:
    def __init__(self, api_url: str, app_id: str, private_key_file: Path) -> None:
        self.api_url = api_url.rstrip("/")
        self.app_id = app_id
        self.private_key = private_key_file.read_bytes()

    def _request(self, method: str, path: str, token: str | None = None, body: dict | None = None) -> object:
        headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "server-review-sentinel/0.1",
        }
        if token:
            headers["Authorization"] = f"Bearer {token}"
        payload = json.dumps(body).encode() if body is not None else None
        if body is not None:
            headers["Content-Type"] = "application/json"
        try:
            with urlopen(Request(self.api_url + path, method=method, headers=headers, data=payload), timeout=30) as response:
                raw = response.read()
        except HTTPError as exc:
            detail = exc.read().decode(errors="replace")
            raise GitHubError(f"GitHub API {method} {path} returned {exc.code}: {detail[:500]}") from exc
        return json.loads(raw) if raw else {}

    def installation_token(self, installation_id: int, permissions: dict[str, str] | None = None) -> str:
        now = int(time.time())
        app_jwt = jwt.encode(
            {"iat": now - 30, "exp": now + 540, "iss": self.app_id},
            self.private_key,
            algorithm="RS256",
        )
        body = {"permissions": permissions} if permissions else None
        result = self._request("POST", f"/app/installations/{installation_id}/access_tokens", app_jwt, body)
        return str(result["token"])

    def pull_request(self, token: str, repo: str, number: int) -> PullRequestContext:
        item = self._request("GET", f"/repos/{repo}/pulls/{number}", token)
        return PullRequestContext(
            repo, number, item["head"]["sha"], item["base"]["sha"],
            item["html_url"], bool(item["base"]["repo"].get("private")),
            bool(item.get("draft")), item.get("state", "unknown"),
        )

    def archive(self, token: str, repo: str, sha: str, target: Path, max_bytes: int) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        request = Request(
            f"{self.api_url}/repos/{repo}/tarball/{sha}",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "User-Agent": "server-review-sentinel/0.1",
            },
        )
        try:
            with urlopen(request, timeout=60) as response:
                length = response.headers.get("Content-Length")
                if length and int(length) > max_bytes:
                    raise GitHubError(f"GitHub archive exceeds configured limit ({max_bytes} bytes)")
                written = 0
                with target.open("wb") as sink:
                    while chunk := response.read(1024 * 1024):
                        written += len(chunk)
                        if written > max_bytes:
                            raise GitHubError(f"GitHub archive exceeds configured limit ({max_bytes} bytes)")
                        sink.write(chunk)
        except HTTPError as exc:
            raise GitHubError(f"cannot download {repo}@{sha}: HTTP {exc.code}") from exc

    def comment(self, token: str, repo: str, number: int, body: str) -> dict:
        comments = self._request("GET", f"/repos/{repo}/issues/{number}/comments?per_page=100", token)
        marker = "<!-- review-sentinel-report -->"
        existing = next(
            (item for item in comments if marker in item.get("body", "") and item.get("user", {}).get("type") == "Bot"),
            None,
        )
        if existing:
            return self._request("PATCH", f"/repos/{repo}/issues/comments/{existing['id']}", token, {"body": body})
        return self._request("POST", f"/repos/{repo}/issues/{number}/comments", token, {"body": body})


def verify_signature(payload: bytes, signature: str, secret: str) -> bool:
    if not signature.startswith("sha256=") or not secret:
        return False
    expected = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
    return hmac.compare_digest(signature[7:], expected)
