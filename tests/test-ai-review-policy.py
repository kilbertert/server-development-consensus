from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/open-code-review.yml"
CODERABBIT = ROOT / ".coderabbit.yaml"
POLICY = ROOT / "SERVER-DEVELOPMENT-CONSENSUS.md"
README = ROOT / "README.md"
CODEX_INSTRUCTIONS = ROOT / "CODEX-DEVELOPER-INSTRUCTIONS.md"


def load_yaml(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return yaml.load(handle, Loader=yaml.BaseLoader)


def test_open_code_review_github_action_is_not_installed() -> None:
    assert not WORKFLOW.exists()
    workflows = ROOT / ".github/workflows"
    assert not any("open-code-review" in path.read_text(encoding="utf-8") for path in workflows.glob("*.y*ml"))


def test_retired_coderabbit_config_is_preserved_but_disabled() -> None:
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
    assert "Devin Review automatically reviews the PR" in normalized_policy
    assert "opened, reopened, or ready for review" in normalized_policy
    assert "does not rerun after every push" in normalized_policy
    assert "the agent requests one re-review" in normalized_policy
    assert "one re-review with `/devin review`" in normalized_policy
    assert "fetch and rebase on the remote task branch" in normalized_policy
    assert "CodeRabbit is the rollback path" in normalized_policy
    assert "AI review remains advisory" in normalized_policy
    assert "never TEAM-MEMORY, host configuration, logs, or credentials" in normalized_policy
    assert "needs human approval before publication" in normalized_policy

    # The triage gate. The distinction it rests on must stay stated in all three
    # governance files, or the gate reads as "AI review became a merge gate".
    for normalized, name in (
        (normalized_policy, "policy"),
        (normalized_readme, "README"),
        (normalized_codex_instructions, "Codex instructions"),
    ):
        assert "conversation resolution" in normalized, name
        assert "non-required" in normalized or "not required" in normalized, name
    assert "Triage is gated; the reviewer's check is not" in normalized_policy
    assert "requires conversation resolution" in normalized_policy
    assert "posts `/devin review` after addressing findings" in normalized_policy

    assert "server's three-layer architecture is explicit" in normalized_readme
    assert "Devin Review automatically reviews the initial ready PR" in normalized_readme
    assert "CI and Rulesets remain the only mandatory merge gates" in normalized_readme
    assert "It does not use a GitHub Action and does not depend on an OCR gateway" in normalized_readme
    assert "delegation mode when one is not" in normalized_readme
    assert "OpenClaw-hosted instance is not a public service" in normalized_readme
    assert "must begin as review-only" in normalized_readme
    assert "approve the model provider and retention boundary" in normalized_readme
    assert "needs human approval before a public GitHub comment is published" in normalized_readme
    assert "`review-sentinel/`" in normalized_readme
    assert "dedicated Codex home" in normalized_policy
    assert "never point it at the interactive `~/.codex` home" in normalized_codex_instructions

    assert "run local `ocr review`" in normalized_codex_instructions
    assert "otherwise invoke OpenCodeReview's delegation mode" in normalized_codex_instructions
    assert "Devin Review automatically reviews a PR" in normalized_codex_instructions
    assert "the agent requests one re-review" in normalized_codex_instructions
    assert "fetch and rebase on the remote task branch" in normalized_codex_instructions
    assert "do not turn speculative model suggestions into an open-ended repair loop" in normalized_codex_instructions
    assert "public comments need human approval after redaction" in normalized_codex_instructions
    assert "Neither Devin Review nor OCR may be a required merge check" in normalized_codex_instructions

    # The retired reviewer must not survive as a named layer in any governance
    # document: a policy that names a component that no longer runs is the
    # defect this assertion exists to prevent.
    assert "PR-Agent" not in normalized_policy
    assert "PR-Agent" not in normalized_readme
    assert "PR-Agent" not in normalized_codex_instructions


def test_ocr_coverage_is_measured_rather_than_assumed() -> None:
    # OCR selects files by extension and path rules, so a change it filters out
    # is reported as a clean run rather than as an unreviewed one. Without this
    # discipline an unreviewed documentation change reads as three green layers.
    policy = POLICY.read_text(encoding="utf-8")
    readme = README.read_text(encoding="utf-8")
    codex_instructions = CODEX_INSTRUCTIONS.read_text(encoding="utf-8")
    normalized_policy = " ".join(policy.split())
    normalized_readme = " ".join(readme.split())
    normalized_codex_instructions = " ".join(codex_instructions.split())

    assert "Coverage must be measured, not assumed" in normalized_policy
    assert "selects files by extension and path rules" in normalized_policy
    assert "reported as a clean run rather than as an unreviewed one" in normalized_policy
    assert "`ocr review --from <default> --to <branch> --preview`" in normalized_policy
    assert "run `ocr review --preview` first" in normalized_readme
    assert "record the layer as **not applicable**" in normalized_readme
    assert "Always run `--preview` first" in normalized_policy
    assert "Always run `--preview` first" in normalized_codex_instructions
    assert "Record the layer as not applicable when it selects nothing" in normalized_policy


def test_engineering_article_release_contract_is_explicit() -> None:
    policy = POLICY.read_text(encoding="utf-8")
    readme = README.read_text(encoding="utf-8")
    codex_instructions = CODEX_INSTRUCTIONS.read_text(encoding="utf-8")
    normalized_policy = " ".join(policy.split())
    normalized_readme = " ".join(readme.split())
    normalized_codex_instructions = " ".join(codex_instructions.split())

    assert "## Engineering Article Publication" in policy
    assert "publication is never an automatic completion requirement" in normalized_policy
    assert "requires explicit human authorization in the current task" in normalized_policy
    assert "Never copy raw chats, hidden reasoning, TEAM-MEMORY bodies or evidence" in normalized_policy
    assert "Do not turn one canary or partial workflow into a universal product claim" in normalized_policy
    assert "clean, current, isolated task branch or worktree of the canonical blog repository" in normalized_policy
    assert "Automated redaction checks are guardrails, not proof of privacy" in normalized_policy
    assert "`draft_ready`, `pr_open`, `merged_waiting_deploy`, `live`, or `blocked`" in normalized_policy
    assert "Do not stash, commit, rebase, discard, or otherwise move another task's work" in normalized_policy

    assert "Engineering Article Release contract standardizes a frequent cross-project workflow" in normalized_readme
    assert "distinguish `merged_waiting_deploy` from `live`" in normalized_readme

    assert "Engineering articles use one explicit public-projection workflow" in normalized_codex_instructions
    assert "do not write, push, merge, or deploy public blog content unless the current task authorizes publication" in normalized_codex_instructions
    assert "Never move another task's uncommitted work" in normalized_codex_instructions


def test_acceptance_and_system_test_contract_is_explicit() -> None:
    policy = " ".join(POLICY.read_text(encoding="utf-8").split())
    readme = " ".join(README.read_text(encoding="utf-8").split())

    assert "## Acceptance And System-Test Evidence" in policy
    assert "Gherkin `Feature`, `Rule`, `Scenario`, `Given`, `When`, and `Then`" in policy
    assert "internal database state is not sufficient as the only `Then` assertion" in policy
    assert "Each case names an ID, environment, preconditions, test data" in policy
    assert "agents are replaceable roles" in policy
    assert "Record traceability from requirement to `Feature`/`Rule`, test case, result, and defect" in policy
    assert "Mutation testing is required for core business rules" in policy
    assert "an agent may not silently relax a requirement to make a test pass" in policy
    assert "A missing, failed, or blocked required case stops the handoff" in policy

    assert "acceptance and system-test contract covers user-visible and cross-system changes" in readme
    assert "Complexity/coverage and mutation analysis are risk-triggered" in readme


def test_worktree_delivery_lifecycle_is_explicit_and_non_destructive() -> None:
    policy = " ".join(POLICY.read_text(encoding="utf-8").split())
    readme = " ".join(README.read_text(encoding="utf-8").split())
    codex_instructions = " ".join(CODEX_INSTRUCTIONS.read_text(encoding="utf-8").split())

    assert "## Git And Worktree Delivery Invariants" in policy
    assert "dev-worktree start TYPE DESCRIPTION [PATH]" in policy
    assert "dev-worktree audit" in policy
    assert "dev-worktree retire PATH" in policy
    assert "preserve marker documents ownership but does not bypass an actual overlap" in policy
    assert "never deletes files, branches, or worktrees automatically" in policy

    assert "committed paths overlap uncommitted paths in another worktree" in readme
    assert "None of these commands automatically delete dirty work or a remote branch" in readme

    assert "Create isolated tasks with `dev-worktree start TYPE DESCRIPTION [PATH]`" in codex_instructions
    assert "this does not bypass the pre-push overlap guard" in codex_instructions
    assert "daily audit reports stale lifecycle states without deleting them" in codex_instructions


def test_policy_runtime_is_one_release_unit() -> None:
    policy = " ".join(POLICY.read_text(encoding="utf-8").split())
    readme = " ".join(README.read_text(encoding="utf-8").split())
    codex_instructions = " ".join(CODEX_INSTRUCTIONS.read_text(encoding="utf-8").split())

    assert "common library, commands, managed hooks, audit units, and configuration are one release unit" in policy
    assert "Deploy them only through the canonical installer" in policy
    assert "do not manually copy an individual policy or tool file into place" in readme
    assert "instead of manually projecting an individual policy or tool file" in codex_instructions


def test_policy_audit_service_uses_the_installer_python_environment() -> None:
    unit = (ROOT / "systemd/dev-policy-audit.service").read_text()
    assert "Environment=PATH=%h/miniconda3/bin:%h/.local/bin:" in unit


def test_review_sentinel_is_review_only_and_least_privilege() -> None:
    manifest = (ROOT / "review-sentinel/github-app-manifest.json").read_text(encoding="utf-8")
    assert '"contents": "read"' in manifest
    assert '"pull_requests": "read"' in manifest
    assert '"issues": "write"' in manifest
    assert '"actions"' not in manifest
    assert '"checks"' not in manifest
    assert '"workflows"' not in manifest
    assert '"administration"' not in manifest
    assert "Review Sentinel" in (ROOT / "review-sentinel/README.md").read_text(encoding="utf-8")
    unit = (ROOT / "review-sentinel/systemd/review-sentinel.service").read_text(encoding="utf-8")
    assert "ProtectKernelModules" not in unit
    assert "RestrictSUIDSGID" not in unit
