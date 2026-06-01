SHELL := /bin/bash
.PHONY: help up down restart rebuild status logs attach doctor

# --- config (override on the command line, e.g. `make up PORT=4100`) ---
# Inline comments are avoided here on purpose: GNU Make keeps trailing
# whitespace before a `#` as part of the value, which would corrupt paths
# and the tmux session name.

# Source clone holding cmd/detent.
DETENT_SRC ?= $(HOME)/projects/digitaldrywood/detent
# Installed binary launched by `up`.
BIN ?= $(HOME)/go/bin/detent
# Live config (a symlink to ./global.yaml after cutover); detent keeps its DB
# and log next to the resolved config file, i.e. in ~/.detent.
CONFIG ?= $(HOME)/.detent/global.yaml
PORT ?= 4000
# tmux session name — deliberately distinct from any 'Detent' editor session.
SESSION ?= detent-orch
ENV ?= dev
LOG_LEVEL ?= debug
LOG := $(HOME)/.detent/detent.log

# Single source of truth for the launch command (token is read at runtime, never stored).
LAUNCH = DETENT_ENV=$(ENV) DETENT_LOG_LEVEL=$(LOG_LEVEL) GITHUB_TOKEN="$$(gh auth token)" $(BIN) --config $(CONFIG) --port $(PORT)

help:
	@echo "Detent orchestration"
	@echo
	@echo "  make up       start the orchestrator detached in tmux session '$(SESSION)'"
	@echo "  make down     stop it (SIGINT, then kill the session)"
	@echo "  make restart  down + up"
	@echo "  make rebuild  go build $(BIN) from $(DETENT_SRC)/cmd/detent, then restart"
	@echo "  make status   is it listening on :$(PORT)?"
	@echo "  make logs     tail $(LOG)"
	@echo "  make attach   tmux attach to '$(SESSION)' (the live TUI dashboard)"
	@echo "  make doctor   run 'detent doctor' against $(CONFIG)"
	@echo
	@echo "  dashboard:    http://localhost:$(PORT)"

up:
	@if lsof -i :$(PORT) -sTCP:LISTEN -t >/dev/null 2>&1; then \
	  echo "already up — something is listening on :$(PORT). Use 'make restart' or 'make attach'."; exit 0; fi
	@command -v gh >/dev/null || { echo "!!! gh not found — needed to mint GITHUB_TOKEN (https://cli.github.com)"; exit 1; }
	@gh auth status >/dev/null 2>&1 || { echo "!!! gh not authenticated — run 'gh auth login --scopes repo,read:org,project'"; exit 1; }
	@tmux new-session -d -s $(SESSION) -n $(SESSION) '$(LAUNCH)'
	@sleep 1
	@echo ">>> started tmux session for '$(SESSION)' — dashboard http://localhost:$(PORT) (make attach to see the TUI)"

# Stop by port (robust: the session name may be re-cased by the tmux server),
# then best-effort kill any session whose name matches SESSION case-insensitively.
down:
	@pid=$$(lsof -i :$(PORT) -sTCP:LISTEN -t 2>/dev/null); \
	if [ -n "$$pid" ]; then echo ">>> stopping detent (pid $$pid on :$(PORT))"; kill -INT $$pid 2>/dev/null || true; sleep 1; fi; \
	sess=$$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -i '^$(SESSION)$$' | head -1); \
	if [ -n "$$sess" ]; then tmux kill-session -t "$$sess" 2>/dev/null || true; echo ">>> killed tmux session '$$sess'"; fi; \
	if [ -z "$$pid$$sess" ]; then echo "nothing on :$(PORT) and no '$(SESSION)' session"; fi

restart: down up

rebuild:
	@echo ">>> building $(BIN) from $(DETENT_SRC)/cmd/detent"
	cd $(DETENT_SRC) && go build -o $(BIN) ./cmd/detent
	@$(MAKE) restart

status:
	@if lsof -i :$(PORT) -sTCP:LISTEN -t >/dev/null 2>&1; then \
	  echo "running: YES (pid $$(lsof -i :$(PORT) -sTCP:LISTEN -t), dashboard http://localhost:$(PORT))"; \
	else echo "running: NO (nothing listening on :$(PORT))"; fi

logs:
	@test -f $(LOG) && tail -f $(LOG) || { echo "no $(LOG) yet — start with 'make up'"; exit 1; }

attach:
	@sess=$$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -i '^$(SESSION)$$' | head -1); \
	if [ -n "$$sess" ]; then tmux attach -t "$$sess"; else echo "no '$(SESSION)' session — run 'make up'"; exit 1; fi

doctor:
	@$(BIN) --config $(CONFIG) doctor
