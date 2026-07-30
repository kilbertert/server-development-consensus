# Review Sentinel

Review Sentinel is the server's minimal self-hosted ClawSweeper-like PR layer.
It is deliberately review-only and is separate from the local OpenCodeReview
CLI and from CodeRabbit.

## Current boundary

- A private GitHub App receives only `pull_request` label events.
- `review-sentinel` queues one review for an exact PR head SHA.
- `review-sentinel-publish` is a separate explicit publication action.
- SQLite provides a durable, single-concurrency queue and exact-head dedupe.
- The Codex worker reviews a temporary base/head archive in a read-only sandbox
  and must return the checked-in JSON schema.
- The publisher uses a fresh installation token and updates one marker-backed
  issue comment.
- The App has no contents write, workflow write, administration, merge, push,
  close, or autofix capability.
- Public repositories are rejected unless explicitly approved; their reports
  remain candidates until a maintainer applies the publication label.
- The worker requires an explicit, dedicated Codex executable and
  `REVIEW_SENTINEL_CODEX_HOME`; it rejects the interactive `/home/claude/.codex`
  home. Codex receives an allowlisted environment and shell commands inherit no
  ambient environment variables. Do not point it at a wrapper containing
  unrelated API keys.
- The service unit uses a read-only system view and only writes its queue state.
- Model and internal Git timeouts become failed jobs without stopping the queue
  worker. Service startup marks interrupted jobs failed and never retries them
  automatically.

This does not copy ClawSweeper's worker fleet, Durable Objects, R2 state repo,
repair, issue implementation, or automerge lanes. Those are intentionally out
of scope until the review-only lane demonstrates value.

## Install

Run as `claude`:

```bash
./ops/review-sentinel/install.sh
PYTHONPATH="$HOME/.local/lib/review-sentinel" \
  python3 -m review_sentinel.cli \
  --env-file "$HOME/.config/review-sentinel/review-sentinel.env" doctor
```

The installer never enables or starts the user service. The generated env file
must remain mode `0600`. Do not commit `app.pem`, the webhook secret, or the
env file.

## GitHub App activation

1. Deploy the webhook endpoint behind an HTTPS reverse proxy. The service binds
   to `127.0.0.1:8765` by default; do not expose it directly.
2. Create a private GitHub App from `github-app-manifest.json`. Install it only
   on explicitly allowlisted repositories.
3. Keep the generated private key and webhook secret in the `claude` config
   directory, set `REVIEW_SENTINEL_APP_ID`, and fill the repository allowlist.
4. Create a dedicated Codex home with only the model configuration/auth needed
   for review (`install -d -m 700 ~/.local/share/review-sentinel/codex-home`),
   set `REVIEW_SENTINEL_CODEX_BIN` to its reviewed executable, and run `doctor`
   again. Do not reuse the interactive Codex home or wrapper.
5. Apply the `review-sentinel` label to request one review. For a public
   repository, inspect the local candidate with
   `review-sentinel show <job-id>`, redact or reject findings as needed, and
   only then apply `review-sentinel-publish`.
6. Verify `/healthz`, the queue state, the exact-head marker comment, and the
   absence of code/branch/merge mutations before considering expansion.

The existing OpenClaw-hosted ClawSweeper App cannot supply this backend. The
owner must create and install this separate App. The installer remains safe and
inactive until that external authorization exists.
