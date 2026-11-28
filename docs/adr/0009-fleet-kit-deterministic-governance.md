---
status: accepted
---

# Fleet-Kit Deterministic Cross-Repo Governance (Superseding AFK Sandbox Adapter)

`server-development-consensus` remains the single normative source for host,
account, workspace, Git delivery, and multi-host fleet invariants. What changes
here is the second layer that projects consume: `kilbertert/afk-bootstrap` is
renamed and refocused as `kilbertert/fleet-kit`, a **zero-copy, 100%
deterministic repository governance and delivery suite**, replacing the
heavyweight AFK coding-sandbox architecture recorded in ADR 0001.

## What was measured

Before retiring the AFK sandbox execution layer, recent workflow runs and merged
PRs were measured across all three adopting repositories (`kilbertert/AI-Ops`,
`kilbertert/genesis-evidence`, `kilbertert/Health-Flow`) on 2026-11-28:

- **`AI-Ops`**: Across the last 20 runs each of `agent-implement.yml`,
  `agent-implement-pr.yml`, `agent-implement-prd.yml`, and `agent-review.yml`,
  successful executions were `0` (all skipped; inactive since early November).
  Scheduled `architecture-review.yml` failed 15 of its last 20 runs. All 12 most
  recent merged PRs (`#1812`–`#1824`) were produced via interactive sessions.
- **`genesis-evidence`**: `agent-implement-pr.yml` (`0/20`), `agent-review.yml`
  (`1/20`), and `agent-update-branch.yml` (`0/20`) had been inactive since
  2026-08-28; scheduled `architecture-review.yml` cancelled 15 of 20 runs.
- **`Health-Flow`**: `agent-implement-pr.yml` (`0/20`), `agent-review.yml`
  (`0/14`), and `agent-update-branch.yml` (`0/20`) had been inactive since
  2026-10-27; scheduled `architecture-review.yml` cancelled 16 of 20 runs.
- **What actually ran continuously and delivered value**: deterministic checks
  and delivery helpers (`CI`/`Tests`/`quality`, `Workflow policy` / ADR checks,
  `Spec Tree`, `Doc Lifecycle`, `Mirror to company GitLab`, PR branch hygiene)
  — none of which depend on `@ai-hero/sandcastle`, Docker sandboxes, or LLMs.
- **Distribution cost**: maintaining copy-pasted `.sandcastle/` (~55 files) and
  9 copied workflows per consumer repository required a 266 KB anchor-patching
  bash script (`upgrade-afk.sh`) and caused template drift across repositories.

## Decision

The server and repository fleet adopts a **three-layer architecture**:

| Layer | Owner | Responsibility |
|---|---|---|
| Layer 1: Host & Delivery Baseline | `server-development-consensus` + private `fleet-ops` | Host/account boundaries, managed Git hooks, worktree lifecycle, port registry, service-host rules, and private operations inventory |
| Layer 2: Cross-Repo Deterministic Governance & Delivery | `kilbertert/fleet-kit` (PUBLIC, renamed from `afk-bootstrap`, legacy archived at tag `legacy-afk-1.7.39`) | Zero-copy opt-in deterministic modules distributed via GitHub Reusable Workflows, Composite Actions, and thin CLIs under floating major tag `@v1`: `Doc-GC`, `Policy & ADR Gate`, `Spec-Tree`, and `Delivery & Repo Hygiene` |
| Layer 3: Cross-Project Memory & Interactive AI Engineering | `Agent-Team-Memory` (PRIVATE MCP) + official `agy` (Gemini) & `Codex` subscriptions | Interactive design, coding, review, long-running `/goal` & `/swarm` work, and persistent engineering memory |

Key invariants for Layer 2 (`fleet-kit`):

1. **Thin-shell consumer contract**: consumer repositories do not copy platform
   scripts or full workflow definitions. They keep only declarative config
   (e.g. `docs/doc-lifecycle.json`, `.fleet-kit.json`), thin ~15–25 line caller
   workflows pinned to `@v1`, and repository-private docs/tools outside platform
   config paths.
2. **Deterministic scope**: `fleet-kit` carries no LLM execution loop, no
   `@ai-hero/sandcastle` runtime, and no per-repository sandbox Docker builds.
3. **Precedence**: `server-development-consensus` baseline > repository-specific
   stricter rules > `fleet-kit` defaults. GitHub Rulesets remain the final merge
   control, preserving exact required check names (such as `Workflow policy`).
4. **Compatibility declaration**: `.afk-bootstrap.json` is superseded by optional
   `.fleet-kit.json` recording `fleet_kit_ref` and `consensus_compatibility`.

## Consequences

- Consumer repositories shed `.sandcastle/`, copied workflows, and sandbox
  images without weakening ADR, spec-tree, doc-lifecycle, or Ruleset gates.
- One fix in `fleet-kit` promoted to `@v1` propagates across all adopting
  repositories with zero migration scripts.
- Reintroducing unattended background AI execution in CI requires a separate,
  evidence-backed decision rather than keeping unused sandbox scaffolding alive.

## Supersedes

`docs/adr/0001-layered-afk-governance.md`, which defined the four-plane AFK
Docker-agent adapter and `.afk-bootstrap.json` template-version contract.
