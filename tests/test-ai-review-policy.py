from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/open-code-review.yml"
CODERABBIT = ROOT / ".coderabbit.yaml"
POLICY = ROOT / "SERVER-DEVELOPMENT-CONSENSUS.md"
README = ROOT / "README.md"
CODEX_INSTRUCTIONS = ROOT / "CODEX-DEVELOPER-INSTRUCTIONS.md"
ACCEPTANCE = ROOT / "acceptance.feature"
REVIEW_TOOL = ROOT / "bin/dev-pr-review"


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
    assert "The server uses a two-layer code-review architecture" in normalized_policy
    assert "OpenCodeReview is retired: its CLI, its delegated skill, and its GitHub Action are gone" in normalized_policy
    assert "Reintroducing a local reviewer is a separate decision" in normalized_policy
    assert "its own acceptance evidence" in normalized_policy
    assert "One automatic Devin Review and at most one re-review are the default budgets" in normalized_policy
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
    assert "the responsible agent owns the loop end to end" in normalized_policy
    assert "the operator audits the recorded dispositions" in normalized_policy

    assert "server's two-layer architecture is explicit" in normalized_readme
    assert "Devin Review automatically reviews the initial ready PR" in normalized_readme
    assert "CI and Rulesets remain the only mandatory merge gates" in normalized_readme
    assert "The local development loop has no dedicated review tool" in normalized_readme
    assert "Reintroducing a local reviewer is a separate decision" in normalized_readme
    assert "OpenClaw-hosted instance is not a public service" in normalized_readme
    assert "must begin as review-only" in normalized_readme
    assert "approve the model provider and retention boundary" in normalized_readme
    assert "needs human approval before a public GitHub comment is published" in normalized_readme
    assert "`review-sentinel/`" in normalized_readme
    assert "dedicated Codex home" in normalized_policy
    assert "never point it at the interactive `~/.codex` home" in normalized_codex_instructions

    assert "The server's two review layers are fixed" in normalized_codex_instructions
    assert "do not run `ocr review` and do not invoke its delegation mode" in normalized_codex_instructions
    assert "Devin Review automatically reviews a PR" in normalized_codex_instructions
    assert "the agent requests one re-review" in normalized_codex_instructions
    assert "fetch and rebase on the remote task branch" in normalized_codex_instructions
    assert "not turn speculative model suggestions into an open-ended repair loop" in normalized_codex_instructions
    assert "public comments need human approval after redaction" in normalized_codex_instructions
    assert "Devin Review may not be a required merge check" in normalized_codex_instructions
    assert "OpenCodeReview is retired and must not be reinstalled, invoked, or re-enabled" in normalized_codex_instructions

    # The retired reviewer must not survive as a named layer in any governance
    # document: a policy that names a component that no longer runs is the
    # defect this assertion exists to prevent.
    assert "PR-Agent" not in normalized_policy
    assert "PR-Agent" not in normalized_readme
    assert "PR-Agent" not in normalized_codex_instructions


def test_the_responsible_agent_owns_the_review_thread_loop() -> None:
    # The ruleset blocks a merge on an unresolved thread, and the reviewer only
    # resolves what it considers addressed. The residual threads used to wait
    # for a human, which meant every agent run ended with open threads it could
    # not close. The loop is now the agent's, and the precondition it rests on
    # is mechanical rather than a convention: dev-pr-review refuses to resolve a
    # thread that carries no reply from the account running it.
    policy = " ".join(POLICY.read_text(encoding="utf-8").split())
    readme = " ".join(README.read_text(encoding="utf-8").split())
    codex_instructions = " ".join(CODEX_INSTRUCTIONS.read_text(encoding="utf-8").split())
    acceptance = ACCEPTANCE.read_text(encoding="utf-8")
    normalized_acceptance = " ".join(acceptance.split())
    tool = REVIEW_TOOL.read_text(encoding="utf-8")

    for normalized, name in (
        (policy, "policy"),
        (readme, "README"),
        (codex_instructions, "Codex instructions"),
    ):
        assert "dev-pr-review" in normalized, name
        assert "answered in the thread" in normalized, name

    assert "resolves that thread itself" in policy or "resolved by the responsible agent" in policy
    assert "becomes an after-the-fact audit" in readme
    assert "owns the loop end to end" in readme
    assert "the responsible agent" in codex_instructions

    # The thread loop and the review budget are two different limits and the
    # text has to say so: the loop is bounded by the budget, not by the tool, so
    # a milestone cannot read as an unbounded re-review sequence. The old
    # wording ("repeats ... until no new finding") stated a termination the tool
    # does not provide.
    for normalized, name in (
        (policy, "policy"),
        (readme, "README"),
        (codex_instructions, "Codex instructions"),
    ):
        assert "up to the milestone's review budget" in normalized, name
    assert "until no new finding and no unanswered thread remain" not in policy

    assert "the agent is refused if it tries to resolve a thread that carries no reply" in normalized_acceptance
    assert "and resolves them itself" in normalized_acceptance

    # The tool, not the prose, is what makes the precondition enforceable.
    assert "resolveReviewThread" in tool
    assert "has no reply" in tool
    assert "close-loop" in tool

    # The human-resolver gate is gone from the governing text. Leaving one
    # sentence behind would let the loop be read as still requiring an operator.
    for normalized, name in (
        (policy, "policy"),
        (readme, "README"),
        (codex_instructions, "Codex instructions"),
        (normalized_acceptance, "acceptance.feature"),
    ):
        assert "resolved by a human" not in normalized, name
        assert "resolved by the reviewer" not in normalized, name
        assert "resolved by its author" not in normalized, name


def test_the_retired_local_reviewer_cannot_be_read_back_in() -> None:
    # A retired layer that survives as prose is the defect this file exists to
    # prevent, and this one is unusually easy to reintroduce: reinstalling the
    # CLI is one npm command, and the instruction that pointed agents at it is
    # in a file the installer writes. The assertions below are fail-closed in
    # both directions — the retirement has to stay stated, and no governance
    # file may still present a local review pass as part of the loop.
    policy = POLICY.read_text(encoding="utf-8")
    readme = README.read_text(encoding="utf-8")
    codex_instructions = CODEX_INSTRUCTIONS.read_text(encoding="utf-8")

    retired = (
        "three-layer code-review architecture",
        "server's three-layer architecture is explicit",
        "The server's three review layers are fixed",
        "`ocr review` is the server's local development review tool",
        "run local `ocr review`",
        "otherwise invoke OpenCodeReview's delegation mode",
        "otherwise invoke its delegation mode as a bounded second opinion",
        "Coverage must be measured, not assumed",
        "run `ocr review --preview` first",
        "A local OCR pass, one automatic Devin Review",
        "Neither Devin Review nor OCR may be a required merge check",
        "OpenCodeReview's GitHub Action is not part of the server architecture",
    )
    for document, name in (
        (policy, "policy"),
        (readme, "README"),
        (codex_instructions, "Codex instructions"),
    ):
        for phrase in retired:
            assert phrase not in document, f"{name} still names the retired local reviewer: {phrase}"

    normalized_policy = " ".join(policy.split())
    assert "OpenCodeReview is retired" in normalized_policy
    assert "no CLI, no delegated skill, and no GitHub Action" in normalized_policy
    assert "migration debt to be removed through a focused pull request" in normalized_policy
    assert "There is no local review pass at this milestone" in normalized_policy
    assert "no `ocr review` runs and no delegated skill is invoked" in normalized_policy
    assert "Triage Devin Review's findings once" in normalized_policy

    normalized_readme = " ".join(readme.split())
    assert "OpenCodeReview was retired on 2026-10-08" in normalized_readme
    assert "are gone rather than merely uninstalled" in normalized_readme

    normalized_codex_instructions = " ".join(codex_instructions.split())
    assert "OpenCodeReview was retired on 2026-10-08" in normalized_codex_instructions

    # The ADR is the record of the decision, not a governance document the
    # installer projects, so it is deliberately exempt from the sweep above.
    adr = (ROOT / "docs/adr/0006-retire-opencodereview.md").read_text(encoding="utf-8")
    assert "OpenCodeReview is retired from the server" in " ".join(adr.split())

    # The acceptance contract carries the retirement too, so a later change that
    # quietly reinstates a local pass has to move the contract, not only prose.
    normalized_acceptance = " ".join(ACCEPTANCE.read_text(encoding="utf-8").split())
    assert "The local review layer is retired rather than retained" in normalized_acceptance
    assert "no `ocr review` runs and no delegated review skill is invoked" in normalized_acceptance
    assert "separate decision that must bring its own acceptance evidence" in normalized_acceptance


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
