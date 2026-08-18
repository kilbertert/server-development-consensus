from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path


def _bool(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    api_url: str
    app_id: str
    private_key_file: Path
    webhook_secret: str
    allowed_repositories: frozenset[str]
    codex_bin: str
    codex_home: Path
    review_timeout_seconds: int
    max_archive_bytes: int
    max_extracted_bytes: int
    max_queue: int
    auto_publish_private: bool
    approved_public_repositories: frozenset[str]
    bind_host: str
    bind_port: int
    trigger_label: str
    publish_label: str
    schema_file: Path

    @classmethod
    def from_env(cls) -> "Settings":
        data_dir = Path(os.environ.get("REVIEW_SENTINEL_DATA_DIR", "/home/claude/.local/state/review-sentinel"))
        allowed = frozenset(
            item.strip().lower()
            for item in os.environ.get("REVIEW_SENTINEL_ALLOWED_REPOSITORIES", "").split(",")
            if item.strip()
        )
        public = frozenset(
            item.strip().lower()
            for item in os.environ.get("REVIEW_SENTINEL_APPROVED_PUBLIC_REPOSITORIES", "").split(",")
            if item.strip()
        )
        return cls(
            data_dir=data_dir,
            api_url=os.environ.get("REVIEW_SENTINEL_GITHUB_API_URL", "https://api.github.com").rstrip("/"),
            app_id=os.environ.get("REVIEW_SENTINEL_APP_ID", ""),
            private_key_file=Path(os.environ.get("REVIEW_SENTINEL_PRIVATE_KEY_FILE", "/home/claude/.config/review-sentinel/app.pem")),
            webhook_secret=os.environ.get("REVIEW_SENTINEL_WEBHOOK_SECRET", ""),
            allowed_repositories=allowed,
            codex_bin=os.environ.get("REVIEW_SENTINEL_CODEX_BIN", ""),
            codex_home=Path(os.environ.get(
                "REVIEW_SENTINEL_CODEX_HOME",
                "/home/claude/.local/share/review-sentinel/codex-home",
            )),
            review_timeout_seconds=max(60, int(os.environ.get("REVIEW_SENTINEL_REVIEW_TIMEOUT_SECONDS", "600"))),
            max_archive_bytes=max(1_048_576, int(os.environ.get("REVIEW_SENTINEL_MAX_ARCHIVE_BYTES", str(256 * 1024 * 1024)))),
            max_extracted_bytes=max(16 * 1024 * 1024, int(os.environ.get("REVIEW_SENTINEL_MAX_EXTRACTED_BYTES", str(1 * 1024 * 1024 * 1024)))),
            max_queue=max(1, int(os.environ.get("REVIEW_SENTINEL_MAX_QUEUE", "20"))),
            auto_publish_private=_bool("REVIEW_SENTINEL_AUTO_PUBLISH_PRIVATE"),
            approved_public_repositories=public,
            bind_host=os.environ.get("REVIEW_SENTINEL_BIND_HOST", "127.0.0.1"),
            bind_port=max(1024, int(os.environ.get("REVIEW_SENTINEL_BIND_PORT", "8765"))),
            trigger_label=os.environ.get("REVIEW_SENTINEL_TRIGGER_LABEL", "review-sentinel"),
            publish_label=os.environ.get("REVIEW_SENTINEL_PUBLISH_LABEL", "review-sentinel-publish"),
            schema_file=Path(os.environ.get("REVIEW_SENTINEL_SCHEMA_FILE", "/home/claude/.local/share/review-sentinel/schema.json")),
        )

    def validate_runtime(self) -> list[str]:
        errors: list[str] = []
        if not self.app_id.isdigit():
            errors.append("REVIEW_SENTINEL_APP_ID is not configured")
        if not self.private_key_file.is_file():
            errors.append(f"GitHub App private key is missing: {self.private_key_file}")
        if not self.webhook_secret:
            errors.append("REVIEW_SENTINEL_WEBHOOK_SECRET is not configured")
        if not self.allowed_repositories:
            errors.append("REVIEW_SENTINEL_ALLOWED_REPOSITORIES is empty")
        if not self.codex_bin:
            errors.append("REVIEW_SENTINEL_CODEX_BIN is not configured")
        else:
            codex_path = Path(self.codex_bin)
            if not codex_path.is_absolute():
                errors.append("REVIEW_SENTINEL_CODEX_BIN must be an absolute path")
            elif not codex_path.is_file() or not os.access(codex_path, os.X_OK):
                errors.append(f"Codex executable is not executable: {codex_path}")
        if self.codex_home.resolve() == Path("/home/claude/.codex"):
            errors.append("REVIEW_SENTINEL_CODEX_HOME must be a dedicated review-only Codex home")
        elif not self.codex_home.is_dir():
            errors.append(f"Dedicated Codex home is missing: {self.codex_home}")
        elif self.codex_home.stat().st_mode & 0o077:
            errors.append(f"Dedicated Codex home must not be accessible by other users: {self.codex_home}")
        return errors
