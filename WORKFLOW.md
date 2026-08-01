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

Keep one persistent `## Codex Workpad` issue comment updated with the plan, validation
evidence, blockers, and final handoff. Every update must contain one `detent-status`
fenced block; Detent reads blockers and human actions only there, never from prose.
`status` must be one of `in_progress`, `blocked`, or `complete`.

```detent-status
schema: 1
status: in_progress
blockers: []
human_action: null
```

Before coding, resolve every native dependency, Workpad blocker, and issue-body
`Depends on:` reference. For a dependency blocker, create GitHub's native
`blocked_by` relation first, then set Workpad `status: blocked` and list its
`ref` and `reason`, and keep a parseable `Depends on: #N` or
`Blocked by: owner/repo#N` line in the issue body so Detent can auto-unblock.
Never reimplement a dependency.

The validation gate is `make check` (the configured `gate.run`; this file must
state it because the orchestrator config is outside your worktree). Run
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
root, and database. If an isolation prerequisite is missing, move the issue to
`Blocked` with the exact blocker; do not compensate by sharing state.

After a merge or abandonment: drop any stash entries you created, then
`git -C $HOME/projects/digitaldrywood/detent worktree remove <workspace>` when
no process is using it, and `worktree prune`. Leave other worktrees alone.

## Tracker Interaction

Detent polls status labels; you own the Workpad and only these label
transitions (keep exactly one `detent:*` status label on the issue):
`Todo -> In Progress`, `Rework -> In Progress`, any state -> `Blocked`, and
`Merging -> Done` after a merge. State names map through `state_map` (identity
plus `Cancelled -> Done`), so `In Progress` is `detent:in-progress`.

Never apply `detent:human-review`. Completion is signaled by
`status: complete` in the Workpad while the issue stays in `In Progress`;
Detent watches the PR gate and promotes to `Merging` itself. A stuck agent
belongs in `Blocked`, never `Human Review`. Reserve `Blocked` for true
human-only blockers (missing credentials, tools, external services, ambiguous
direction); agent-recoverable PR maintenance — conflicts, stale or missing
current-head CI, retrigger pushes — belongs in `Rework`.

## REST Budget Discipline

GraphQL and REST have separate ~5,000/hr budgets, and the orchestrator's own
polling needs the GraphQL headroom. Keep routine agent work on REST:

- Watch CI via `gh api repos/<o>/<r>/commits/<sha>/check-runs` or
  `gh run watch <run-id> --exit-status`; never loop `gh pr checks --watch` or
  `gh pr view`.
- Merge via `gh api --method PUT repos/<o>/<r>/pulls/<N>/merge
  -f merge_method=squash -f sha=<sha>`; never `gh pr merge`.
- Prefer `gh api repos/...` REST reads over `gh pr view --json` /
  `gh issue view --json`; status changes are label updates over REST.
- On a GraphQL rate-limit error, switch the operation to REST instead of
  waiting for the hourly reset.

Do not use GitHub Actions as an edit loop: batch local fixes, run focused
tests then the full gate locally, and push once per validated batch.

## State Flow

Use the current Detent state as the source of truth for which section applies.
`Backlog`, `Human Review`, `Done`, and `Cancelled` are never worked.

### For Todo

1. Move the issue to `In Progress`.
2. Initialize the Workpad with the plan, acceptance criteria, validation plan, and `in_progress` status.
3. Fetch `origin/main`, confirm the worktree branch is based on it, and resolve dependencies.
4. Reproduce a reported behavior before changing code; implement the smallest complete change.
5. Run focused tests, then the full validation gate.
6. Commit, push, and open or update a PR filling the template (`Summary`, `Fixes #N`, `Test Plan`). If the PR is a draft, mark it ready yourself (`gh pr ready`, idempotent) — humans never mark Detent PRs ready.
7. Re-check PR comments, reviews, and CI on the latest head; address actionable feedback.
8. Leave the issue in `In Progress`. Set Workpad `status: complete` with no blockers or human action only when the PR is non-draft, references the issue, and the gate and current-head CI are green with no actionable review remaining. Detent auto-promotes directly to `Merging`; never use `Human Review`.

If a required gate cannot run because of missing tools, auth, secrets, or
external access, move the issue to `Blocked` with the exact failed command and
the human action needed — never declare `complete`.

### For In Progress

Re-read the issue, PR, comments, and Workpad, then continue from the current state.
When implementation is complete, run the full gate and apply Todo's completion rule.

### For Rework

Re-read all human, CI, and bot feedback, move the issue to `In Progress`, fix,
push, rerun the full gate, and apply Todo's completion rule.

### For Merging

1. Rebase the PR branch onto current `origin/main`, run the validation gate on
   the rebased branch as a fast pre-push guard, and push.
2. Watch CI on the pushed head via REST; wait for every check to pass and
   every automated review to be addressed (no `CHANGES_REQUESTED`, no pending
   bot review).
3. Merge via the REST merge endpoint with the exact head sha, then move the
   issue to `Done`.
4. End with exactly one terminal outcome:
   - PR merged and issue moved to `Done`;
   - issue moved to `Rework` with an actionable defect;
   - issue remains in `Merging` with the external blocker recorded in the
     `detent-status` block and Workpad. Never move back to `Todo` or
     `Human Review`.

## Admission Criteria

Used by the scheduled admission pass to decide which `Backlog` issues to
propose for `Todo`. Detent proposes; a human accepts. Each subsection
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

### Readiness

An agent must be able to tell when it is done.

A precise symptom plus expected behavior satisfies this. A literal
"Acceptance criteria" heading is **not** required and its absence is not
a disqualifier — a bug report with evidence, cause, and file:line is
ready. What fails this dimension is a wish with no checkable end state.

An issue whose `Depends on:` reference is not merged into `origin/main`
is not ready; leave it in `Backlog`.

An issue with no `detent-agent` effort block is not ready. Effort is a
deliberate operator choice, and an issue admitted without one dispatches
on the fleet default — which silently under-resources exactly the
subsystem, concurrency, and recovery work that most needs `xhigh`. Leave
it in `Backlog` and say the block is missing. This gate is unnecessary
once admission itself recommends an effort and writes it on admit
(detent#1571); until then it is the only thing preventing an
effort-less dispatch.

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
