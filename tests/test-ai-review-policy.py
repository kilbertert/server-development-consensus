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


def test_open_code_review_workflow_is_bounded_advisory_transport() -> None:
    workflow = load_yaml(WORKFLOW)
    triggers = workflow["on"]
    assert set(triggers) == {"workflow_dispatch", "issue_comment"}
    assert triggers["workflow_dispatch"]["inputs"]["force"]["default"] == "false"

    review = workflow["jobs"]["review"]
    assert review["timeout-minutes"] == "15"
    assert "pull_request" not in triggers

    steps = {step["name"]: step for step in review["steps"]}
    guard = steps["Enforce one review per head SHA"]
    guard_script = guard["with"]["script"]
    assert "open-code-review-head:${headSha}" in guard_script
    assert "alreadyReviewed && !force" in guard_script

    action = steps["Run OpenCodeReview"]
    assert action["continue-on-error"] == "true"
    assert action["with"]["review_concurrency"] == "1"
    assert '"max_completion_tokens":4096' in action["with"]["llm_extra_body"]

    serialized = WORKFLOW.read_text(encoding="utf-8")
    assert "OpenCodeReview / review" not in serialized
    assert "checks.create" not in serialized
    assert "pull_request_target" not in serialized


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
    assert "OpenCodeReview's GitHub Action is optional transport only" in normalized_policy
    assert "ClawSweeper is a separate GitHub PR/issue queue and evidence reviewer" in normalized_policy
    assert "A local OCR pass and at most one managed PR review round are the default budgets" in normalized_policy
    assert "never TEAM-MEMORY, host configuration, logs, or credentials" in normalized_policy
    assert "needs human approval before publication" in normalized_policy

    assert "default development-time review uses local OpenCodeReview" in normalized_readme
    assert "delegation mode when one is not" in normalized_readme
    assert "OpenClaw-hosted instance is not a public service" in normalized_readme
    assert "must begin as review-only" in normalized_readme
    assert "approve the model provider and retention boundary" in normalized_readme
    assert "needs human approval before a public GitHub comment is published" in normalized_readme

    assert "run local `ocr review`" in normalized_codex_instructions
    assert "otherwise invoke OpenCodeReview's delegation mode" in normalized_codex_instructions
    assert "do not turn speculative model suggestions into an open-ended repair loop" in normalized_codex_instructions
    assert "public comments need human approval after redaction" in normalized_codex_instructions
    assert "Neither managed AI review nor OCR may be a required merge check" in normalized_codex_instructions
