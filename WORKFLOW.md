---
tracker:
  kind: github
  endpoint: https://api.github.com/graphql
  api_key: $GITHUB_TOKEN
  github_status_source: label
  repository: digitaldrywood/detent
  status_label_prefix: "detent:"
  observed_states:
    - Backlog
    - Blocked
    - Human Review
  active_states:
    - Todo
    - In Progress
    - Rework
    - Merging
  terminal_states:
    - Done
    - Cancelled
  state_map:
    Cancelled: Done
  dependency_auto_unblock:
    enabled: true
    source_states:
      - Blocked
    target_state: Todo
    readiness: terminal_or_merged
polling:
  # Label-backed status polling uses REST issue/label endpoints. A 2-min
  # cadence keeps the board responsive while leaving GraphQL budget for
  # operations that have no REST equivalent.
  interval_ms: 120000
server:
  host: 0.0.0.0
  port: 4000
  kanban:
    mode: integration
workspace:
  root: ~/code/detent-workspaces
  source_root: ~/projects/digitaldrywood/detent
agent:
  # Merge train: keep global throughput at 5, but serialize the final
  # rebase/push/merge so concurrent merge candidates do not invalidate
  # each other's CI. States omitted from max_concurrent_agents_by_state
  # share the global pool.
  # Restored to 5 (full throughput): the two root causes of the earlier
  # exhaustion are fixed — host TCP/socket churn (sysctl msl=1000 +
  # portrange.first=16384 + #311 process-group reaping) and the 552-pt board
  # poll (#313/#314 gutted it to single-digit points; budget holds at ~5000).
  max_concurrent_agents: 5
  max_concurrent_agents_by_state:
    Merging: 1
  dispatch_priority_by_state:
    - Merging
    - Rework
    - In Progress
    - Todo
  # hotfix label jumps the queue within a state — used to cut hotfix releases.
  # priority marks backlog items that should dispatch ahead of unlabeled work
  # once promoted to Todo.
  dispatch_priority_by_label:
    - hotfix
    - priority
    - bug
  max_turns: 20
  # Trial: reattach orphaned provider threads on restart (detent#1155/PR #1175)
  # instead of fresh continuations — falls back safely if resume fails.
  resume_orphaned_sessions: true
  experimental_thread_resume: true
  # Kill runaway sessions at 4x the observed median (7.7M tokens); the worst
  # outlier hit 55M while p90 is 23M, so this cap only cuts the pathological
  # tail (doctor runaway_session_tokens finding).
  max_session_tokens: 30842000
  # This project's review-flow choice: no human review. Completed issues wait
  # in In Progress for the PR gate (CI green), then promote directly to
  # Merging (gate_wait_state: source). Human Review is never entered unless
  # the optout label is applied or the gate wait times out. This project does
  # not require a GitHub bot PR review signal for promotion; CI and no P1
  # findings are the promotion criteria.
  auto_promote:
    enabled: true
    quiet_seconds: 0
    gate_wait_state: source
    optout_label: requires-human-review
    allowed_issue_labels: []
codex:
  # Deliberately unpinned: the Codex CLI default manages the model, so this
  # survives provider model retirements and picks up generation upgrades
  # automatically. Telemetry resolves the effective model from the session
  # since #1103, so pricing attribution works without a pin. Reasoning
  # effort is left at the provider default; not all models accept a
  # model_reasoning_effort override.
  command: codex --config shell_environment_policy.inherit=all app-server
  approval_policy: never
  # Full access: agents run git fetch/worktree against the source repo,
  # need network for `go mod download`, and write to the shared Go build/module
  # cache (~/go, ~/.cache/go-build) which lives outside the worktree.
  thread_sandbox: danger-full-access
  turn_sandbox_policy:
    type: dangerFullAccess
gate:
  kind: command
  run: make check
  require_automated_review: false
hooks:
  after_create: |
    SOURCE_REPO=$HOME/projects/digitaldrywood/detent
    ISSUE_ID="$(basename "$PWD")"
    BRANCH_NAME="detent/$ISSUE_ID"
    git -C "$SOURCE_REPO" fetch origin main
    git -C "$SOURCE_REPO" worktree prune
    # Prune stale local detent/* branch refs (merged/abandoned issues whose
    # worktree is already gone). git refuses to delete a branch checked out in an
    # active worktree, so in-flight work is protected; the current issue's branch
    # is skipped and (re)created by the worktree add below. GitHub's
    # auto-delete-head-branches only cleans the REMOTE; this keeps the local
    # source clone tidy.
    git -C "$SOURCE_REPO" for-each-ref --format='%(refname:short)' refs/heads/detent/ | while IFS= read -r _b; do
      [ "$_b" = "$BRANCH_NAME" ] && continue
      git -C "$SOURCE_REPO" branch -D "$_b" >/dev/null 2>&1 || true
    done
    # The Go workspace backend creates the worktree natively (git worktree add)
    # from workspace.source_root before this hook runs, so we no longer add it
    # here. This hook now only keeps origin/main fresh and prunes stale state.
---
You are working on **Detent** — a Go agent-orchestrator delivered as a
single binary — on GitHub issue `{{ issue.identifier }}`
(repo `digitaldrywood/detent`).

Detent is now self-hosted: it dispatches the agents that build it. Work
items are release-readiness and feature issues. Some issues carry a
**Depends on:** line — do not start an issue whose dependencies are not yet
merged; if a dependency is missing, move to `Blocked` with the exact blocker.

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the issue is still in an
  active state. Resume from the current workspace state instead of
  restarting from scratch.
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

Follow `CLAUDE.md` and `AGENTS.md` if present in the repo. They are the
project authority for layout, formatting, validation, and review
conventions. Match the canonical Go conventions: Go 1.26; feature-packaged
`internal/`; interface + factory for pluggable backends; constructor DI
(no wire/fx); `log/slog`; Echo; sqlc + goose; `modernc.org/sqlite`;
Templ + HTMX + Tailwind v4; air; golangci-lint v2. Reference projects:
`$HOME/projects/digitaldrywood/{digitaldrywood,pyroapex}` and
`$HOME/projects/corylanou/website-template`.

## Detent Isolation Contract

Every Detent worktree must run validation without sharing mutable
runtime state with another worktree. Before running anything, verify the
current workspace has:

- A worktree-local branch and git metadata created by
  `hooks.after_create`. The branch is `detent/<issue-id>` and the
  workspace is a `git worktree` of the source repo at
  `$HOME/projects/digitaldrywood/detent`.
- All build output stays inside this worktree. The Go **module cache**
  (`$HOME/go/pkg/mod`) and **build cache** (`$HOME/.cache/go-build`) are
  shared and safe to use — they are content-addressed. Do not override
  `GOFLAGS`/`GOCACHE`/`GOMODCACHE` to point at another worktree, and do
  not write generated code (`*_templ.go`, sqlc output) outside this
  worktree.
- No reliance on the running orchestrator's process state. Detent is
  itself running on `http://127.0.0.1:4000`; do not bind to that port
  from inside the workspace (tests that need a server must use port 0 /
  an ephemeral port).
- Never stop, restart, signal, kill, replace, or otherwise disrupt the
  live Detent dogfood process on `127.0.0.1:4000` unless the human
  explicitly authorizes that exact action in the current conversation.
  If validation needs a Detent server, start a separate isolated test
  instance on port 0 or another non-production port with its own config,
  workspace root, and database.

If any isolation prerequisite is missing, move the issue to `Blocked`
with the exact blocker and the human action needed. Do not compensate by
sharing port 4000 or editing files outside the worktree.

## Detent Tracker Interaction

Detent polls GitHub repository issues by configured Detent status labels
and spawns this session, but it does not post the workpad comment on
your behalf. You own the workpad and a scoped part of the issue
lifecycle. Use GitHub APIs to:

1. Post the persistent `## Codex Workpad` comment on the underlying
   issue.
2. Move issue status **only** for these transitions, by keeping exactly
   one configured `detent:*` status label on the issue (remove any
   existing `detent:*` status label, then add the target label):
   `Todo -> In Progress`, `Rework -> In Progress`, any state ->
   `Blocked`, and `Merging -> Done` after a merge.

Never apply `detent:human-review` yourself. On successful completion,
leave the issue in `In Progress` and signal completion through the
Workpad `detent-status` block (below); Detent watches the PR gate and
promotes the issue to `Merging` itself. Promotion to `Merging` and any
entry into `Human Review` are Detent's transitions, not yours.

Translate Detent state names through this config's `state_map` before
choosing the label. The current config uses identity translation for
every active state plus `Cancelled -> Done`, so `Todo` maps to
`detent:todo`, `In Progress` maps to `detent:in-progress`, and
`Cancelled` maps to `detent:done`.

## Workpad Status Contract

Every Workpad update must include exactly one `detent-status` fenced
block. Detent reads status, blocker, and human-action declarations from
that block; narrative sentences are never read as signals. `status`
must be one of `in_progress`, `blocked`, or `complete` — no other value
is valid.

While working:

```detent-status
schema: 1
status: in_progress
blockers: []
human_action: null
```

On successful completion (PR open, not draft, references the issue,
validation green, no actionable review comments):

```detent-status
schema: 1
status: complete
blockers: []
human_action: null
```

For dependency blockers, use this order:

1. Create GitHub's native `blocked_by` dependency relation.

```sh
BLOCKED_NUMBER=<blocked-issue-number>
BLOCKER_NUMBER=<blocker-issue-number>
BLOCKER_ID="$(gh api repos/{owner}/{repo}/issues/$BLOCKER_NUMBER --jq '.id')"
gh api --method POST "repos/{owner}/{repo}/issues/$BLOCKED_NUMBER/dependencies/blocked_by" -F issue_id="$BLOCKER_ID"
```

2. Declare the blocker in the Workpad status block.

```detent-status
schema: 1
status: blocked
blockers:
  - ref: "owner/repo#123"
    reason: "waiting for the dependency to merge"
human_action: null
```

3. Legacy fallback during the deprecation window: if native dependencies
   are unavailable, keep a machine-readable issue-body line such as
   `Blocked by: #123` or `Depends on: owner/repo#123`.

## Workflow States

- `Backlog`: do not work. Stop and wait for a human to move the issue
  to `Todo` (gates: dependencies must be merged first).
- `Todo`: move to `In Progress`, then begin implementation.
- `In Progress`: continue implementation.
- `Blocked`: do not code. Use only when Detent cannot continue because
  a true human action or local prerequisite is missing. If the blocker is
  dependency-based, the issue body must contain a machine-readable
  `Depends on:` or `Blocked by:` line naming the GitHub issue or PR
  references, not only Workpad prose. If the issue already has an open PR
  and the blocker is merge conflicts, stale/missing current-head CI, or
  other agent-recoverable PR maintenance, move it to `Rework` instead of
  `Blocked`.
- `Human Review`: do not code, and never enter it yourself. This
  project's configured flow skips human review: completed issues stay in
  `In Progress` while Detent watches the PR gate, then Detent promotes
  them directly to `Merging` (CI green, no P1 bot review findings). An
  issue appears in `Human Review` only when a human applies the
  `requires-human-review` opt-out label or the gate wait times out.
- `Rework`: address requested changes, then run the full pre-review gate
  again.
- `Merging`: rebase onto `origin/main`, watch CI, merge once green, then
  move the issue to `Done`.
- `Done`, `Cancelled`: terminal. Do nothing.

## Safe Concurrency Rollout

`Merging` is the only state intentionally serialized. Keep
`agent.max_concurrent_agents_by_state.Merging = 1` so only one agent
performs the final rebase/push/merge sequence at a time.

Do not cap `Todo`, `In Progress`, or `Rework`. Those states share the
global `agent.max_concurrent_agents` pool so Detent keeps workers busy
while merge candidates wait for CI or a clean base branch.

A stuck or misconfigured agent should be moved to `Blocked`, never
`Human Review`. Use `Blocked` for "Detent can't continue without a
human". "The PR is ready" is signaled by `status: complete` in the
Workpad while the issue stays in `In Progress` — not by any label move.

## Blocked Handoff Contract

Blocked items must be recoverable by Detent when the blocker clears.
Before moving an issue to `Blocked`:

- If waiting on another GitHub issue or PR, ensure the issue body contains
  a parseable line such as `Depends on: #415` or
  `Blocked by: digitaldrywood/detent#415`. Do not put dependency
  references only in the `## Codex Workpad` comment.
- If the blocked item has an open PR and Detent can plausibly repair it
  by rebasing, resolving conflicts, pushing a retrigger commit, or
  rerunning validation, move it to `Rework` and record the exact recovery
  action in the Workpad. Do not leave agent-recoverable PR work in
  `Blocked`.
- Use `Blocked` without dependency metadata only for true human-only
  blockers such as missing credentials, missing local tools, unavailable
  external services, ambiguous product direction, or explicit human
  approval requirements.
- In the Workpad `### Blockers` section, include both the human-readable
  explanation and the exact structured references already present in the
  issue body.

## Operating Rules

1. Keep a single persistent GitHub issue comment headed
   `## Codex Workpad`. Use it for the plan, acceptance criteria,
   validation evidence, blockers, and final handoff notes, and include
   exactly one `detent-status` block (see Workpad Status Contract) in
   every update. Do not scatter progress across multiple comments.
2. Work in the Detent-created worktree only.
3. Keep changes scoped to the GitHub issue. Respect the issue's
   **Depends on:** line — if a dependency PR is not merged into
   `origin/main`, move to `Blocked`; do not reimplement the dependency.
4. New or modified Go functions that change observable behavior require
   corresponding tests. Use stdlib table-driven tests (no testify). The
   coverage gate is **70%** once there is testable code. Generated code
   (`*_templ.go`, sqlc output) and pure glue are excluded by
   `.golangci.yml` and need no tests.
5. Before every commit or PR, run `git status` and `git diff`.
6. Never bypass pre-commit hooks (`--no-verify`, `SKIP=...`, disabled
   hooks, hook config edits) unless the human authorizes it in the same
   turn. If a hook fails, fix the blocker or move to `Blocked`; do not
   commit known-broken work.
7. If a no-commit-to-branch hook fails, the workspace is on the wrong
   branch. The worktree branch is `detent/<issue-id>`; switch to it
   and rerun checks before committing.
8. After code changes, run the validation gate (below) and confirm it
   is green before pushing.
9. If you discover meaningful out-of-scope work, file a separate GitHub
   issue in `Backlog` rather than expanding the current issue.

## Validation Gate

Run from the repo root.

- **Once a `Makefile` exists** (created in issue #3): run `make check`
  (build + `golangci-lint run` + `go vet` + `go test -race ./...` +
  the 70% coverage gate). Also run `make generate` (templ + sqlc +
  tailwind) before committing if you touched templates, queries, or CSS,
  and commit the generated output.
- **Before the Makefile exists** (issue #2 scaffold, or any gap): run
  `go build ./... && go vet ./... && go test ./...`. If there is no Go
  code yet, the scaffold issue defines "green" as `go build ./...`
  succeeding and `detent --help` running.

Treat any failure as blocking: fix it, add/adjust tests, commit, push,
and rerun the gate from the top.

## Required Execution Flow

For `Todo`:

1. Move the GitHub issue to `In Progress`.
2. Create or update the `## Codex Workpad` comment (plan + acceptance).
3. Fetch latest `origin/main`; confirm the worktree branch is based on
   current `origin/main`. Confirm every **Depends on:** issue is already
   merged (its code is present on `origin/main`); if not, ensure the
   dependency is recorded as a parseable `Depends on:` or `Blocked by:`
   line in the issue body, then move to `Blocked`.
4. For a bug/behavior change, reproduce or confirm the behavior before
   changing code.
5. Implement the smallest complete change that satisfies the issue.
6. Run focused tests for the touched packages.
7. Run the validation gate and confirm it is green.
8. Commit and push the branch.
9. Open or update a GitHub PR, filling the PR template (Summary,
   `Fixes #N`, Test Plan).
10. Run the pre-review gate below.
11. Do NOT move the issue to `Human Review`. Leave the issue in
    `In Progress` and update the Workpad `detent-status` block to
    `status: complete` with `blockers: []` only after the pre-review
    gate passes. Detent auto-promotes the issue directly to `Merging`
    when the PR gate (CI) is green.

For `In Progress`:

1. Re-read the issue, PR, comments, and `## Codex Workpad`, including
   the `detent-status` block.
2. Continue from the current repository and Project state.
3. If implementation is complete, run the pre-review gate, then update
   the Workpad `detent-status` block to `status: complete` with
   `blockers: []` and `human_action: null` only when the gate passes.
   Do NOT move the issue to `Human Review`; leave it in `In Progress`
   and let Detent auto-promote it to `Merging` once the PR gate is
   green.

For `Rework`:

1. Re-read all human and bot feedback.
2. Move the issue to `In Progress`.
3. Fix the requested changes.
4. Push updates to the PR.
5. Run the full pre-review gate again.
6. When the gate passes, update the Workpad `detent-status` block to
   `status: complete` and leave the issue in `In Progress`; Detent
   auto-promotes it back to `Merging` once the PR gate is green. Do NOT
   move it to `Human Review`.

For `Merging`:

1. Confirm the linked PR exists and the issue was moved to `Merging` by
   Detent auto-promotion (from the `In Progress` gate wait) or explicit
   human action.
2. Rebase the PR branch onto current `origin/main`.
3. Run the validation gate locally one more time on the rebased branch.
   This is a fast pre-push guard; it does not replace current-head GitHub CI.
4. Push the rebased branch.
5. Watch CI via the REST check-runs API (cheap; preserves the GraphQL
   budget): poll `gh api repos/<owner>/<repo>/commits/<HEAD_SHA>/check-runs`
   (or `gh run watch <run-id> --exit-status`) — **do NOT** use
   `gh pr checks --watch` or `gh pr view` in a loop. Wait for every check
   to pass on the current HEAD sha.
6. Confirm all automated reviews are addressed: every reviewer is
   `APPROVED`, no `CHANGES_REQUESTED` is open, and no pending bot review
   is in flight.
7. Merge via the REST API (not `gh pr merge`, which routes through
   GraphQL): `gh api --method PUT repos/<owner>/<repo>/pulls/<N>/merge
   -f merge_method=squash -f sha=<HEAD_SHA>`.
8. Move the GitHub issue to `Done`.

If any merging step is blocked by required human approval, failed CI,
missing auth, or another external blocker, keep the issue in `Merging`
and update the `## Codex Workpad` with the exact blocker. Do not move
back to `Todo` or `Human Review`.

## GraphQL Budget Discipline

GitHub meters **two separate** hourly budgets per user: ~5,000 **GraphQL
points/hr** and ~5,000 **REST requests/hr**. Detent's orchestrator polls
issue status through GitHub's REST issue and label endpoints. **Every
agent must keep routine work on the REST budget** so GraphQL remains
available for operations that have no REST equivalent.

Rules for agent `gh` usage:

- **CI status / watching:** use REST — `gh api repos/<o>/<r>/commits/<sha>/check-runs`
  or `gh run watch <run-id> --exit-status`. **Never** loop `gh pr checks --watch`
  or `gh pr view` to poll CI; those route through GraphQL and a multi-minute
  poll loop can burn hundreds of points per PR.
- **Merging:** `gh api --method PUT repos/<o>/<r>/pulls/<N>/merge -f merge_method=squash -f sha=<sha>`
  (REST). `gh pr merge` uses GraphQL.
- **Reading PR/issue/comment/review state:** prefer `gh api repos/...` REST
  endpoints over `gh pr view --json` / `gh issue view --json` (GraphQL).
- **Reserve GraphQL strictly** for operations that have no REST
  equivalent. Status changes in this workflow are label updates and should
  use REST.
- If you see `API rate limit exceeded` on a GraphQL call, the REST budget is
  almost certainly still healthy — switch the operation to REST rather than
  waiting for the hourly reset.

## Mandatory Pre-Review Gate

Required for every Detent item before declaring `status: complete` in
the Workpad `detent-status` block.

1. Confirm there is an open GitHub PR for the branch.
2. Run the validation gate (above). Every step must pass. Treat any
   failure as blocking.
3. If it fails, fix the failure, add/update tests, commit, push, and
   rerun from step 1.
4. Re-check PR comments, inline review comments, and CI checks after the
   latest push.
5. Update the `## Codex Workpad` with the gate result, the tests added
   or updated, and any unresolved blockers.
6. If the PR is in draft, mark it ready (`gh pr ready <num>`) —
   idempotent. Always run it before step 7 so PR draft state and the
   completion signal never disagree. Humans never mark Detent PRs ready;
   Detent does.
7. Set `status: complete` in the Workpad `detent-status` block only when
   all are true (the issue stays in `In Progress`):
   - PR is open and references the issue (`Fixes #N`).
   - PR is not in draft.
   - The validation gate passed after the latest meaningful code change.
   - Required tests pass.
   - No actionable review comments remain unaddressed or unexplained.

If any required gate cannot run because of missing tools, auth, secrets,
or external access, move the issue to `Blocked` and keep the Workpad
status `blocked` — never declare `complete`. Record the exact failed
command, the blocker, and the human action needed in the
`## Codex Workpad`.

If the gate fails because the PR is out of date, merge-conflicting, or
missing checks on a current head that the agent can update by pushing,
move the issue to `Rework` and perform that recovery there. Reserve
`Blocked` for cases where the agent cannot take the next action.

## Cleanup After Merge Or Abandonment

Clean up workspace-owned resources once an issue is merged or abandoned:

- Remove the git worktree from the source repo with
  `git -C $HOME/projects/digitaldrywood/detent worktree remove
  <workspace>` when no process is using it, then
  `git -C $HOME/projects/digitaldrywood/detent worktree prune`.
- Leave other worktrees' state alone.

## CI Push Discipline

Do not use GitHub Actions as an edit loop. Before opening or updating a
PR, batch local fixes and run the fastest relevant local validation
first: `gofmt`/`templ fmt` changed files, run focused package tests,
then the full validation gate before the final push when feasible.

Push once after local validation passes. During review or rework,
collect fixes locally and push one update instead of force-pushing after
every small edit.

Operate autonomously end-to-end unless blocked by missing requirements,
secrets, or permissions.
