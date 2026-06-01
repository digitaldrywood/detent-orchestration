# detent-orchestration

The live configuration that drives [**Detent**](https://github.com/digitaldrywood/detent)
as it builds itself.

Detent is a Go agent-orchestration system: it dispatches Codex coding agents against a
GitHub Projects board, deterministically and gated (CI + Codex code-review + a serialized
merge train). This repository is the config Detent runs **on its own repository** — it
dogfoods itself. The issues Detent works through are its own feature and release-readiness
issues; the PRs you see merged into `digitaldrywood/detent` were opened by agents launched
from the config in this repo.

> **Use this as a template.** This is a complete, working Detent setup. To stand up
> your own board, copy `WORKFLOW.md` + `global.yaml` (and the `Makefile`), then follow
> [Bootstrap On A New Machine](https://github.com/digitaldrywood/detent#bootstrap-on-a-new-machine-humans-and-ai-agents)
> in the Detent README. New to Detent? Start with the
> [Detent README](https://github.com/digitaldrywood/detent#readme).

## What's here

| File | Purpose |
|------|---------|
| `global.yaml` | Multi-project config: the agent pool size, scheduler, and the list of projects Detent manages. |
| `WORKFLOW.md` | The per-project workflow — tracker (GitHub Projects v2) binding, worktree hooks, the Codex agent prompt, and the required Todo → Human Review → Merging → Done execution flow + merge gate. |
| `Makefile` | Launch/operate the orchestrator (`make up/down/restart/rebuild/logs/status/attach`). |

## Run it

```bash
make up        # start the orchestrator detached in tmux session 'detent-orch'
make attach    # watch the live TUI dashboard  (also: http://localhost:4000)
make logs      # tail ~/.detent/detent.log
make rebuild   # rebuild the binary from the source clone and restart
make down      # stop
```

`make up` reads `GITHUB_TOKEN` at runtime via `gh auth token` — no secret is ever stored in
this repo. It launches the installed `detent` binary with `--config ~/.detent/global.yaml`.

## How the config and runtime state are wired

`detent` keeps its SQLite database and log **next to the resolved global config file**.
To keep this repository the source of truth for config while keeping runtime state out of
git, `~/.detent/global.yaml` is a **symlink** to this repo's `global.yaml`:

```
~/.detent/global.yaml  ->  ~/projects/digitaldrywood/detent-orchestration/global.yaml
~/.detent/detent.db        # runtime state stays in ~/.detent (lexical dir of the config path)
~/.detent/detent.log
```

So `--config ~/.detent/global.yaml` resolves to the file in this repo (edits and commits
happen here), while `detent.db` / `detent.log` stay in `~/.detent`.

## The dogfood loop

1. Edit `WORKFLOW.md` (agent prompt, hooks, caps) or `global.yaml` (add/remove a project).
2. Detent hot-reloads the change live — no restart.
3. `git commit` the change. The running system and the repo never drift.

> Live reload of `WORKFLOW.md` ships today; live add/remove of projects from `global.yaml`
> is tracked in [digitaldrywood/detent#211](https://github.com/digitaldrywood/detent/issues/211).
