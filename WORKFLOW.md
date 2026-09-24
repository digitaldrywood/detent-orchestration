You are working on **Detent** — a Go agent-orchestrator delivered as a
single binary — on GitHub issue `{{ issue.identifier }}`
(repo `digitaldrywood/detent`). Detent is self-hosted: it dispatches the
agents that build it, and the live dogfood process is running on
`http://127.0.0.1:4000` while you work.

{% if attempt %}
Continuation context: this is retry attempt #{{ attempt }} because the
issue is still in an active state. Resume from the current workspace
state instead of restarting from scratch.
{% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Issue node id: {{ issue.id }}
Title: {{ issue.title }}
Current Detent status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Follow `CLAUDE.md` and `AGENTS.md`; they are the project authority for
layout, formatting, validation, and review conventions. Canonical Go
conventions: Go 1.26; feature-packaged `internal/`; interface + factory
for pluggable backends; constructor DI; `log/slog`; Echo; sqlc + goose;
`modernc.org/sqlite`; Templ + HTMX + Tailwind v4; air; golangci-lint v2.
Reference projects:
`$HOME/projects/digitaldrywood/{digitaldrywood,pyroapex}` and
`$HOME/projects/corylanou/website-template`.

## Detent Protocol

The assigned issue authorizes implementation and validation without confirmation.
Follow the Detent-appended Blocked handoff section for the canonical Workpad,
dependency, human-question, completion, and tracker ownership contract. Do not
copy that contract here; see Detent's docs/templates/blocked-handoff.md.

The validation gate is `make check-fast` (the configured `gate.run`; this file must
state it because the orchestrator config is outside your worktree). Race tests, coverage, and nilaway run once in the merge queue, not in your session; do not run `make check` unless a change touches the safety-critical orchestrator files listed in CLAUDE.md. Run
`make generate` before committing if you touched templates, queries, or CSS,
and commit the generated output. New or changed observable behavior requires
stdlib table-driven tests (no testify); the coverage gate is 70%, with
generated code excluded by `.golangci.yml`. Never bypass pre-commit hooks
(`--no-verify`, `SKIP=...`) without explicit human authorization in the same
turn; if a no-commit-to-branch hook fails you are on the wrong branch — switch
to `detent/<issue-id>` and rerun.

If meaningful out-of-scope work is discovered, file a separate issue in
`Backlog` instead of expanding the current one.

## Isolation Contract

The workspace is a `git worktree` of `$HOME/projects/digitaldrywood/detent` on
branch `detent/<issue-id>`, created by `hooks.after_create`. All build output
stays inside the worktree; the shared Go module and build caches
(`$HOME/go/pkg/mod`, `$HOME/.cache/go-build`) are content-addressed and safe —
do not repoint `GOFLAGS`/`GOCACHE`/`GOMODCACHE`, and do not write generated
code outside the worktree. Never use `git stash` — stashes are repo-global
across worktrees; commit WIP to the issue branch and squash or amend before
the final push.

Never bind to port 4000, and never stop, restart, signal, kill, or replace the
live Detent process on `127.0.0.1:4000` unless the human explicitly authorizes
that exact action in the current conversation. Tests or experiments that need
a server use port 0 or an isolated instance with its own config, workspace
root, and database. If isolation is missing, report the exact failure; do not share state.

After a merge or abandonment: drop any stash entries you created, then
`git -C $HOME/projects/digitaldrywood/detent worktree remove <workspace>` when
no process is using it, and `worktree prune`. Leave other worktrees alone.

## REST Budget Discipline

GraphQL and REST have separate ~5,000/hr budgets, and **REST is the scarce one**.
Agents share the orchestrator's credential, so agent polling and orchestrator
dispatch draw down the same REST bucket. On 2026-08-08 REST hit 0/5000 twice and
suppressed dispatch (`skip_reason: github_rest_capacity_paused`) while GraphQL
sat at ~4,700/5,000 — about 6% used. Treat REST as the budget to protect.

CI watching is where the budget goes. Poll as little as possible:

- Watch CI with a single blocking `gh run watch <run-id> --exit-status`.
  Prefer this over any polling loop — it is one call, not one per interval.
- If you must poll `gh api repos/<o>/<r>/commits/<sha>/check-runs`, use an
  interval of **60s or more** and cap the total iterations. Never poll faster
  than 60s, never loop unbounded, and never loop `gh pr checks --watch` or
  `gh pr view`.
- Never poll `api.github.com` with bare `curl`. Unauthenticated requests get the
  60/hr anonymous IP limit and are invisible to budget accounting.
- Merge via `gh api --method PUT repos/<o>/<r>/pulls/<N>/merge
  -f merge_method=squash -f sha=<sha>`; never `gh pr merge`.
- Status changes are label updates over REST.
- When REST is the constrained budget and the same read is available on GraphQL,
  use GraphQL — it has idle headroom. On a GraphQL rate-limit error, fall back to
  REST rather than waiting for the hourly reset.

Do not use GitHub Actions as an edit loop: batch local fixes, run focused
tests then validate locally as specified in Detent Protocol, and push once per validated batch.

## Browser Verification In Workers

When a UI-visible change requires browser verification, use the browser tooling
this worker actually has:

- Use the **`chrome-devtools` MCP server** (`mcp__chrome-devtools__*`). It is
  configured for Codex workers and is worktree-aware, so each worktree gets an
  isolated Chrome profile.
- Do **not** route through the `claude-in-chrome` skill or
  `mcp__claude-in-chrome__*` tools. Those need the Claude Chrome extension,
  which no Detent worker has, and that skill forbids substituting
  chrome-devtools — so choosing it parks the issue in `Blocked` while working
  browser tooling sits unused.
- Treat browser tooling as missing only if
  `mcp__chrome-devtools__navigate_page` is genuinely absent from the tool list.
  Verify before declaring the gate unsatisfiable.

## State Flow

Use the current Detent state as the source of truth for which section applies.
`Backlog`, `Human Review`, `Done`, and `Cancelled` are never worked.

### For Todo

1. Re-read the issue and current Workpad.
2. Initialize the Workpad using the appended handoff contract.
3. Fetch `origin/main`, confirm the worktree branch is based on it, and resolve dependencies.
4. Reproduce a reported behavior before changing code; implement the smallest complete change.
5. Run focused tests, then follow the validation rule in Detent Protocol.
6. Commit, push, and open the PR as a **draft** (`gh pr create --draft`) filling the template (`Summary`, `Fixes #N`, `Test Plan`). CI does not run on drafts; keep pushing to the draft while you iterate.
7. Do not spawn sub-agents for review; the GitHub review bot reviews the PR. Address its findings when they arrive. Then mark the PR ready yourself (`gh pr ready`, idempotent) — humans never mark Detent PRs ready. Marking ready is the one CI run for this PR. After that, push to the ready PR only to address review findings on it, or when Detent routes the issue to `Rework`; never ask for permission to do either.
8. Re-check PR comments, reviews, and CI on the latest head; address actionable feedback. Review-bot threads never gate the merge on their own; fix what is actionable, resolve the thread, and move on.
9. Report completion through the appended handoff contract only when the PR is
   non-draft, references the issue, local validation is green, and no actionable
   review remains. PR checks are skipped by design (INV-5): full CI runs only in
   the merge queue, so skipped PR checks plus a green local gate are sufficient.
   A failed PR check still blocks completion. Report exact validation failures.

### For In Progress

Re-read the issue, PR, comments, and Workpad, then continue from the current state.
When implementation is complete, follow the validation rule in Detent Protocol and apply Todo's completion rule.

### For Rework

Re-read all human, CI, and bot feedback, fix,
validate and push as specified in Detent Protocol, and apply Todo's completion rule.

### For Merging

1. Rebase the PR branch onto current `origin/main`, validate the
   rebased branch as specified in Detent Protocol, and push.
2. Watch CI on the pushed head via REST; wait for every check to pass and
   every automated review to be addressed (no `CHANGES_REQUESTED`, no pending
   bot review).
3. Merge via the REST merge endpoint with the exact head sha, then report the merge in the Workpad.
4. Report exactly one terminal outcome through the Workpad:
   - PR merged and issue moved to `Done`;
   - issue moved to `Rework` with an actionable defect;
   - issue remains in `Merging` with the external blocker recorded in the
     `detent-status` block and Workpad. Never move back to `Todo` or
     `Human Review`.

## Admission Criteria

Used by the scheduled admission pass to decide which `Backlog` issues to
propose for `Todo`. Configured high-confidence proposals are automatically
admitted; lower-confidence proposals require operator acceptance. Each subsection
below is a scoring dimension. A proposal must quote the rule it relied
on, verbatim, and an issue that satisfies no dimension is not proposed.

### Alignment

Admit, in this order of preference:

1. **Fleet-visible defects.** A reproducible failure with a symptom an
   operator has actually seen: a crash, a killed healthy worker, a
   contradictory record, a lane that stops advancing. This includes
   flaky or timing-sensitive tests that fail CI or block a release
   cut — a red release gate is an operator-visible symptom.
2. **Safety-critical correctness.** Defects in the orchestrator brakes
   and dispatch controls named in `CLAUDE.md` —
   `implement_progress.go`, `backend_capacity.go`,
   `spend_progress.go`, `ranking.go`. These outrank features even when
   the symptom is mild.
3. **Work that removes a standing human step.** Anything that turns a
   recurring operator intervention into something the system does or
   surfaces on its own.
4. **Board legibility where an operator has to guess.** A state the
   dashboard cannot explain, a number nobody can attribute, a lane whose
   contents mean two different things.

Do not admit, regardless of how well argued:

5. **Process encoded into the binary.** Criteria, review policy, and
   orchestration conventions belong in this file or in operator config,
   never in generic Go.
6. **Connector or tracker breadth nobody has asked for.** New backends
   and unused capability surface wait for a project that needs them.
7. **UI change with no operator complaint and no baseline regression.**
   Polish is not a priority on its own.
8. **Umbrella and epic issues.** Flat issues with `Depends on:` lines
   only. Decompose before admitting anything inside.
9. **Features and new or expanded mechanisms without a human's scope
   approval.** Any issue that adds capability, surface, configuration,
   a brake, breaker, lease, park, recovery path, reservation, or reason
   code stays in `Backlog` until a human moves it, regardless of who
   filed it or how the title is typed. Only a fix with recorded runtime
   evidence (log lines, database rows, attempt ids, a reproducible
   failure) whose remedy removes or consolidates may be admitted without
   a human. Operator decision 2026-09-14.

### Readiness

An agent must be able to tell when it is done.

A precise symptom plus expected behavior satisfies this. A literal
"Acceptance criteria" heading is **not** required and its absence is not
a disqualifier — a bug report with evidence, cause, and file:line is
ready. What fails this dimension is a wish with no checkable end state.

An issue whose `Depends on:` reference is not merged into `origin/main`
is not ready; leave it in `Backlog`.

A missing `detent-agent` effort block alone does not make an issue unready.
Admission recommends an effort using the Issue effort selection section and
writes it before moving the issue to Todo. Existing effort overrides remain
authoritative. Require a valid recommendation before admitting an issue.

When an issue fails only on readiness, say what is missing rather than
admitting it.

### Size

Admit only what can plausibly be finished and validated in a single
agent run. Oversized work is the strongest predictor of a failed
dispatch, so decompose first and admit the pieces.

### Safety Gates

An issue touching the safety-critical files named under Alignment must
state, in its own acceptance criteria, the 90% exact-file coverage floor
and the `FuzzSafetyCriticalOrchestratorBoundaries` seed requirement.
Without both, it is not ready no matter how important the defect is.

A `hotfix`-labeled issue must carry recorded runtime evidence of the
failure — log lines, capacity snapshots, database rows — not only a
narrative root cause, and its regression test must reproduce that
recorded sequence, not the narrative. A narrative can be wrong while a
green test built from it passes; that is exactly how detent#1600
shipped PR #1601, a hotfix whose test encoded a misdiagnosis and fixed
nothing (see detent#1602). If the evidence and the narrative disagree,
the evidence wins. An implementer who cannot reproduce the recorded
sequence in a test must say so on the issue rather than substituting a
test of the explanation.

## Issue effort selection

Model and effort come from the instance config, split by stage: Codex Astra
(`gpt-6-astra`) plans at `low` effort and validates at `medium`, and Codex Sol
(`gpt-6-sol`) builds (code, rework, merge) at `high`. Issues labelled
`complexity:very-complex` escalate to Astra at `medium`.

Every issue must include an explicit `detent-agent` block, with `model` unset:

```detent-agent
schema: 1
effort: high
```

- `high` — the default; use it unless the issue states a documented reason not to.
  Each stage clamps it to its own ceiling, so planning still runs at `low` and
  validation at `medium`.
- `medium` or `low` — an exception that requires a written reason in the issue;
  it lowers the build effort below what the fleet was measured at.
- `xhigh` and `max` — operator-designated only; never assign automatically.

Concurrency, recovery, routing, multiple files, or a new endpoint alone never
justify changing the effort. Preserve intentional operator exceptions and leave
`model` unset: a per-issue model overrides every stage, including Astra planning
and validation.

## Mechanism moratorium

Effective 2026-09-10 until the operator lifts it. Detent has grown a large set
of interacting self-protection mechanisms (brakes, breakers, leases, parks,
recovery sweeps, revocations, reconcilers). Their interactions are now the main
source of incidents.

- Do not add a new brake, breaker, lease, park, recovery path, revocation,
  reason code, or reconciliation loop.
- A fix for a misbehaving mechanism must remove or consolidate a mechanism, or
  state in the PR why it cannot. "Add a guard for the new case" is not a fix.
- Infrastructure failures (backend startup, protocol errors, workspace hooks)
  are attributed to the instance, never to the issue.
- The orchestrator is the only writer of tracker lane state; workers report
  outcomes and never write lane labels.
- Do not add configuration keys, CLI subcommands, or dashboard surfaces to work
  around a mechanism. Fix the mechanism.
- Machine-filed issues carry an origin stamp and a fingerprint; never file a
  duplicate of an open issue, comment on it instead.
