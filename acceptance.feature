Feature: Layered consensus and AFK governance

  Rule: The server baseline remains authoritative across AFK execution planes

    Scenario: An AFK adapter cannot weaken a server invariant
      Given a repository uses an AFK execution adapter
      When the adapter declares its workflow and repository-specific rules
      Then the server-development-consensus baseline remains the higher-priority rule
      And a stricter repository rule is allowed
      And a weaker AFK rule is rejected before delivery

    Scenario: An incompatible AFK template is blocked
      Given a repository records an AFK template and consensus compatibility window
      When the current consensus version is outside that window or the declaration is missing
      Then the implementation or delivery check fails with the versions and range
      And no task branch is pushed for delivery

    Scenario: A container cannot deliver directly to the default branch
      Given an AFK agent runs inside a Docker container
      When it attempts to push the protected default branch
      Then the portable policy check rejects the operation
      And the host runner rejects the delivery
      And the GitHub Ruleset rejects any remaining attempt

    Scenario: Container credentials are narrower than host delivery credentials
      Given a host runner has a delivery token and a separate read-only agent token
      When an AFK profile creates a Docker sandbox
      Then only the explicit read-only token is mapped to container GH_TOKEN
      And AGENT_PAT and host delivery credentials remain outside the container

    Scenario: Codex uses the managed long-context defaults
      Given the installed Codex model catalog advertises a maximum context of at least 872000 tokens
      When the server consensus installer updates the user's Codex configuration
      Then the global context window is 872000 tokens
      And automatic compaction is configured at 700000 tokens
      And unrelated Codex settings remain unchanged

  Rule: Exceptions are bounded and auditable

    Scenario: A legitimate AFK implementation difference is recorded
      Given Docker isolation is different from an upstream runner implementation
      When an owner submits a structured exception
      Then the exception names the invariant, reason, scope, compensating control, owner, approval, and expiry
      And it cannot waive account boundaries, secret isolation, or merge gates

  Rule: Repository class decides which rules a repository is subject to

    Scenario: An externally governed repository keeps its own delivery process
      Given a repository is classified as externally governed
      When a developer commits a non-conventional message and pushes the default branch to that repository's own remote
      Then the server commit convention and default-branch guard do not reject the operation
      And the repository's own hooks receive the original hook input

    Scenario: Host boundaries still apply to an externally governed repository
      Given a repository is classified as externally governed
      When a task worktree for it is created outside the workspace worktree location
      Then the worktree location rule still reports the violation
      And the account boundary, secret isolation, port registry, and host rules remain in force

    Scenario: An unrecorded repository class stays server-managed
      Given a repository records no repository class
      When a developer attempts an operation that violates the server contract
      Then the operation is rejected by the server-managed rules
      And the repository is never exempted by default

    Scenario: An unreadable or invalid repository class fails closed
      Given a repository records an unreadable or invalid repository class
      When a commit, merge, or push is attempted
      Then the operation stops with a repository class error
      And the repository is never silently exempted
