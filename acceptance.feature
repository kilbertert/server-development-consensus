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

  Rule: Exceptions are bounded and auditable

    Scenario: A legitimate AFK implementation difference is recorded
      Given Docker isolation is different from an upstream runner implementation
      When an owner submits a structured exception
      Then the exception names the invariant, reason, scope, compensating control, owner, approval, and expiry
      And it cannot waive account boundaries, secret isolation, or merge gates
