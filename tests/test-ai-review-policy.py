from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/open-code-review.yml"
CODERABBIT = ROOT / ".coderabbit.yaml"


def load_yaml(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return yaml.load(handle, Loader=yaml.BaseLoader)


def test_open_code_review_is_bounded_advisory_fallback() -> None:
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
