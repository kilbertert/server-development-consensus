# PR-Agent Acceptance Probe

Temporary end-to-end probe for automatic pull request review. This change is
not intended to merge.

Acceptance criteria:

- the initial review starts from the pull request event;
- a push alone does not start another review;
- one agent-authored `/review` comment starts the bounded re-review.
