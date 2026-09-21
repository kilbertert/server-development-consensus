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

  Rule: A service host carries services, and the development host carries none

    Scenario: The service host model is present in every installed policy copy
      Given the consensus source declares a `service host` role and the migration contract
      When the canonical installer deploys the release unit
      Then every installed policy copy contains that role and that contract
      And no installed copy differs from the canonical source
      And the policy audit reports no drift

    Scenario: A service identity is scoped to one project
      Given a service host runs one project's processes
      When its service identity is inspected
      Then it is a system account with no login shell, no password, no sudo, and no shared group
      And its environment file is readable by that identity and by no other service identity
      And no project's credential is reachable by a process belonging to a different project

    Scenario: A move is not complete when the new deployment starts serving
      Given a service is being moved to a service host
      When the new deployment passes its acceptance check and takes traffic
      Then switching traffic and retiring the previous instance are separate steps
      And the previous deployment stays available until the switch is verified
      And the exposure was closed from observed traffic rather than from which ports were listening

  Rule: Reaching another host is a fixed, gated operation

    Scenario: A host whose recorded key does not match is unreachable
      Given a project declares a target that resolves to a recorded host
      And the recorded host public key is not the one the host presents
      When any operation is attempted against that target
      Then the operation is refused before it reaches the host
      And the refusal names the identity failure rather than a command error

    Scenario: A service host refuses an unidentifiable write
      Given a target is recorded with a service-class role
      When a file is written without an artifact identity
      Then the write is refused
      And the refusal states what would make it acceptable
      And nothing is transferred

    Scenario: An unrecorded host is not guessed at
      Given a target names a host absent from the private record
      When any operation is attempted against it
      Then the operation is refused
      And the host is not contacted

    Scenario: A declaration cannot carry an address into a public repository
      Given a project declares the hosts it reaches
      When the declaration is reviewed
      Then it names targets by logical name only
      And addresses, fingerprints, and credentials live outside version control

  Rule: Exactly one automated reviewer holds the first-pass pull-request slot

    Scenario: An enrolled repository receives one automated review
      Given a repository is enrolled for Devin Review and has observed pull-request traffic
      When a pull request is opened or a draft is marked ready for review
      Then Devin Review posts exactly one review on that head
      And no other automated reviewer comments on the pull request

    Scenario: A retired reviewer is stood down rather than deleted
      Given the automatic review layer has been reassigned
      When an enrolled repository receives a pull request
      Then no PR-Agent comment appears, while its unit, virtualenv and credential directory stay on disk
      And CodeRabbit is stood down through its GitHub App installation with its configuration preserved

    Scenario: Automated review is never a merge gate
      Given a pull request carries Devin Review findings
      When the required merge gates are evaluated
      Then the findings remain candidates that need human confirmation
      And the deterministic CI checks and the Ruleset alone decide the merge

    Scenario: An auto-fix commit does not strand the task branch
      Given auto-fix is enabled and Devin Review has pushed a fix commit to the task branch
      When the responsible agent continues work on that branch
      Then the agent fetches and rebases on the remote task branch before pushing
      And the branch is never force-pushed

  Rule: A delivery surface is retired only after its integration is verified

    Scenario: A merged task branch is retired from the local workspace
      Given the daily policy audit reports a local task branch as stale
      When the branch head carries a merged pull request and its tree matches the hosting merge commit
      Then the branch is retired
      And a branch without a verified merge is reported rather than deleted
      And remote branch deletion and local branch deletion are separate, reported operations

  Rule: A deployment artifact is not a delivery surface

    Scenario: A runner working directory is not a managed repository
      Given a self-hosted runner checks code out under its own working directory
      When the policy audit scans the projects root
      Then the checkout is reported as a runner working directory
      And it is not held to the managed-repository delivery metadata rules
      And a repository outside those directories is still held to them
