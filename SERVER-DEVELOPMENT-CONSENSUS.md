# Server Development Consensus

This is the non-negotiable development policy for this server. It applies to
all projects, interactive shells, Codex sessions, Claude Code sessions, and
other agent tools. Project instructions may add stricter rules but must not
weaken this policy.

## Account Boundary

- `claude` is the only interactive development account and owns developer
  tools, project source, caches, user services, and AI-tool configuration.
- `root` is for explicit host maintenance only: packages, system services,
  Docker daemon administration, Nginx, SSH, accounts, and recovery. Never
  develop, run AI tools, start project applications, or store source in
  `/root`.
- `ranlei` is a locked, non-login service identity for `/opt/ranlei-blog`. Do
  not use it for development or change the account without an explicit service
  migration.

## Files And Runtimes

- Create and maintain projects only below `/home/claude/Projects`.
- `/home/ranlei/Project` and related `/home/ranlei/*` paths are compatibility
  symlinks. Do not create new work there, replace them, or remove them until
  live service and Docker references have been explicitly migrated.
- User AI tools, Conda, caches, VS Code Server, and user configuration belong
  below `/home/claude`. System Node under `/usr/local` is root-maintained.
- Keep new developer-owned files private by default (`umask 027`). Do not use
  ACLs, cross-user groups, or recursive cross-account ownership changes as a
  shortcut.

## Mandatory Git Workflow

The default branch (`main`, `master`, or the remote's configured default) is a
protected integration branch. It must represent reviewed, tested, deployable
code. Normal development never happens directly on it.

For every code, configuration, schema, infrastructure-as-code, or maintained
documentation change:

1. Start from a clean, current default branch. Fetch with pruning and update
   using fast-forward only.
2. Create one short-lived branch for one logical task before editing tracked
   files. Use `feat/`, `fix/`, `refactor/`, `docs/`, `test/`, `chore/`, or
   `hotfix/`, followed by a short lowercase kebab-case description. Agent-owned
   branches may use their established prefix, such as `codex/`.
3. Make focused commits. Each commit should leave the branch coherent; use the
   project's commit convention, or clear Conventional Commit style when none
   exists. Never commit secrets, local credentials, `.env` contents, or
   unrelated generated artifacts.
4. Run the repository's formatter, static checks, tests, and build in
   proportion to the change. Add or update tests for regressions and non-trivial
   behavior. Record any check that cannot be run.
5. Push the task branch and open one pull request. Multiple commits and pushes
   belong to that same branch and PR; each push reruns deterministic CI, not an
   unbounded AI review. Do not create a new PR for every commit.
6. Keep the PR focused, describe the behavior and verification, and resolve
   review threads. All required deterministic CI checks must complete
   successfully. AI review is advisory by default: verified findings must be
   fixed, while false positives, findings outside the agreed threat model, and
   accepted risks require explicit human triage rather than repeated model runs.
7. Merge through the Git hosting service after the branch is current and every
   required check passes. Prefer squash merge unless project history requires a
   different method. Delete the merged task branch and resync the local default
   branch.

Direct pushes, force pushes, local merges pushed to the default branch, and
using `--no-verify` to bypass the server guard are prohibited. Do not weaken or
disable a GitHub Ruleset, required deterministic check, or Git hook to make a
change pass. AI review workflows may be paused or reconfigured through an
explicit governance decision when their cost, latency, or false-positive rate
is disproportionate; that is not a CI bypass.

If existing uncommitted work is found on a default branch, preserve it by
creating a task branch in place before continuing. Never discard it merely to
make the worktree clean. Read-only investigation and analysis tasks do not
require a branch.

## Pull Request Gate

- Required merge gates are deterministic repository checks: tests, build,
  formatting, static analysis, migrations, and other project-specific CI.
- CodeRabbit is the preferred managed AI reviewer where its GitHub App has been
  explicitly authorized. It is opt-in by `review-ready` label or the
  `@coderabbitai review` command, does not review drafts, and does not
  automatically rerun after every push.
- OpenCodeReview is a manual fallback invoked with `/open-code-review` or a
  workflow dispatch. It is advisory, single-concurrency, time-bounded, and must
  never be a required merge check or run automatically on each push. The
  `review-ready` label is reserved for CodeRabbit and must not trigger
  OpenCodeReview. OpenCodeReview reviews a given PR head SHA at most once by
  default; a repeat requires an explicit human workflow dispatch with the force
  option after a material change or an incomplete infrastructure run.
- AI findings are review candidates, not authoritative verdicts. A human must
  confirm severity and applicability. One full AI review per ready PR is the
  default budget; further runs require a material code change or explicit human
  request. Stop the run when its time or cost exceeds its likely review value.
- Public repositories use an active Ruleset with no bypass actors, require a
  pull request, require the branch to be current, and require the selected
  deterministic CI checks.
- Private repositories on GitHub Free cannot enable Rulesets or legacy branch
  protection. The same workflow is still mandatory, and the local guard still
  prohibits direct default-branch pushes, but the hosting account must be
  upgraded before remote enforcement is equivalent.

## Agent Behavior

For a task that will edit maintained files, agents must first inspect the
worktree, current branch, default branch, remotes, and existing user changes. If
the current branch is the default branch, create a task branch before editing.
Work with existing changes and never discard them without explicit approval.

Creating a local task branch is a normal preparation step. Committing, pushing,
opening a PR, merging, releasing, or deploying remains subject to the user's
requested scope. If the task does not authorize those remote or delivery
actions, leave verified changes on the task branch and report the remaining
delivery step. Never substitute a direct default-branch push.

Before changing host-level state, inventory affected accounts, services, paths,
and live references and preserve a rollback path. After a migration, verify
ownership, account/group state, service cgroups, health endpoints, and
compatibility references. Never delete archives or compatibility paths merely
to make the filesystem appear cleaner.

## Internal Knowledge And Public Projection Boundary

- TEAM-MEMORY, agent memory, engineering notes, logs, commit streams,
  repository metadata, filesystem paths, service topology, account details,
  credentials, and other internal operating records are private by default.
- Never directly or bulk-sync raw internal records to a public service. Public
  material must be a separate artifact created through explicit selection,
  redaction, editing, and human approval before publication.
- A public projection is not an authoritative engineering record. It must not
  overwrite, approve, or otherwise mutate its internal source of truth.
- Public feedback may create an inbox candidate for later review, but it must
  never automatically modify or approve formal TEAM-MEMORY entries.
- When the sensitivity or publication authority of information is unclear,
  keep it private and request explicit direction.

## Services And Docker

- Persistent development applications run as enabled `claude` user units in
  `/home/claude/.config/systemd/user`, managed with `systemctl --user`. Do not
  use root `tmux`, `nohup`, or a login shell as a service supervisor.
- System daemons remain root-managed. Do not alter `/etc`, SSH, Nginx, Docker
  daemon configuration, accounts, groups, or system services without explicit
  authorization for that host change.
- Project-scoped Compose work may run as `claude`; Docker daemon administration
  remains a root responsibility. Do not use `/root` paths or perform broad
  image, container, or volume cleanup without explicit approval.

## Emergency Changes

Urgent production work still uses `hotfix/* -> PR -> deterministic CI ->
merge`. Urgency shortens scope and response time; it does not remove review.

Only a real incident in which GitHub or the required review service is
unavailable and waiting would materially worsen impact may use a break-glass
path. It requires explicit human approval in the current task, a recorded
incident reason, the smallest possible change, relevant verification, and
immediate restoration of every disabled guard. A retrospective PR and review
must follow. Agents cannot self-authorize break-glass actions.

<!-- team-memory:start -->
## Personal Team Memory

Use `/home/ranlei/Project/Agent-Team-Memory` as the shared long-term memory
repository. Before engineering work, retrieve only relevant active current
project, shared, and system memories. Inbox entries are candidates, not facts.
Project memories default to `project`; use `system` only for agent or server
infrastructure. Before the final response, complete the memory evaluation.
Never store secrets, full chats, or temporary reasoning, and never commit or
push memory automatically.
<!-- team-memory:end -->
