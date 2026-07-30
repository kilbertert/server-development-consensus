from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/open-code-review.yml"
CODERABBIT = ROOT / ".coderabbit.yaml"
POLICY = ROOT / "ops/server-development-consensus/SERVER-DEVELOPMENT-CONSENSUS.md"
README = ROOT / "ops/server-development-consensus/README.md"
CODEX_INSTRUCTIONS = ROOT / "ops/server-development-consensus/CODEX-DEVELOPER-INSTRUCTIONS.md"


def load_yaml(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return yaml.load(handle, Loader=yaml.BaseLoader)


def test_open_code_review_github_action_is_not_installed() -> None:
    assert not WORKFLOW.exists()
    workflows = ROOT / ".github/workflows"
    assert not any("open-code-review" in path.read_text(encoding="utf-8") for path in workflows.glob("*.y*ml"))


def test_coderabbit_is_opt_in_and_non_incremental() -> None:
    config = load_yaml(CODERABBIT)
    auto_review = config["reviews"]["auto_review"]
    assert auto_review["enabled"] == "false"
    assert auto_review["drafts"] == "false"
    assert auto_review["auto_incremental_review"] == "false"
    assert auto_review["labels"] == ["review-ready"]


def test_review_roles_and_budget_are_explicit_across_governance_files() -> None:
    policy = POLICY.read_text(encoding="utf-8")
    readme = README.read_text(encoding="utf-8")
    codex_instructions = CODEX_INSTRUCTIONS.read_text(encoding="utf-8")
    normalized_policy = " ".join(policy.split())
    normalized_readme = " ".join(readme.split())
    normalized_codex_instructions = " ".join(codex_instructions.split())

    assert "## Development Review Sequence" in policy
    assert "`ocr review` is the server's local development review tool" in normalized_policy
    assert "Run it with an approved local provider, or use its delegation mode" in normalized_policy
    assert "OpenCodeReview's GitHub Action is not part of the server architecture" in normalized_policy
    assert "ClawSweeper is a separate GitHub PR/issue queue and evidence reviewer" in normalized_policy
    assert "A local OCR pass and at most one managed PR review round are the default budgets" in normalized_policy
    assert "never TEAM-MEMORY, host configuration, logs, or credentials" in normalized_policy
    assert "needs human approval before publication" in normalized_policy

    assert "server's three-layer architecture is explicit" in normalized_readme
    assert "It does not use a GitHub Action and does not depend on an OCR gateway" in normalized_readme
    assert "delegation mode when one is not" in normalized_readme
    assert "OpenClaw-hosted instance is not a public service" in normalized_readme
    assert "must begin as review-only" in normalized_readme
    assert "approve the model provider and retention boundary" in normalized_readme
    assert "needs human approval before a public GitHub comment is published" in normalized_readme
    assert "ops/review-sentinel/" in normalized_readme
    assert "dedicated Codex home" in normalized_policy
    assert "never point it at the interactive `~/.codex` home" in normalized_codex_instructions

    assert "run local `ocr review`" in normalized_codex_instructions
    assert "otherwise invoke OpenCodeReview's delegation mode" in normalized_codex_instructions
    assert "do not turn speculative model suggestions into an open-ended repair loop" in normalized_codex_instructions
    assert "public comments need human approval after redaction" in normalized_codex_instructions
    assert "Neither managed AI review nor OCR may be a required merge check" in normalized_codex_instructions


def test_review_sentinel_is_review_only_and_least_privilege() -> None:
    manifest = (ROOT / "ops/review-sentinel/github-app-manifest.json").read_text(encoding="utf-8")
    assert '"contents": "read"' in manifest
    assert '"pull_requests": "read"' in manifest
    assert '"issues": "write"' in manifest
    assert '"actions"' not in manifest
    assert '"checks"' not in manifest
    assert '"workflows"' not in manifest
    assert '"administration"' not in manifest
    assert "Review Sentinel" in (ROOT / "ops/review-sentinel/README.md").read_text(encoding="utf-8")
