SHELL := /bin/bash
.PHONY: help up down restart rebuild status logs attach doctor

# --- config (override on the command line, e.g. `make up PORT=4100`) ---
DETENT_SRC ?= $(HOME)/projects/digitaldrywood/detent   # source clone holding cmd/detent
BIN        ?= $(HOME)/go/bin/detent                     # installed binary launched by `up`
CONFIG     ?= $(HOME)/.detent/global.yaml               # live config (symlink -> ./global.yaml); DB + log live beside it in ~/.detent
PORT       ?= 4000
SESSION    ?= detent-orch                               # tmux session name — deliberately distinct from any 'Detent' editor/Claude session
ENV        ?= dev
LOG_LEVEL  ?= debug
LOG        := $(HOME)/.detent/detent.log

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
	@if tmux has-session -t $(SESSION) 2>/dev/null; then \
	  echo "already up (session '$(SESSION)'). Use 'make restart' or 'make attach'."; exit 0; fi
	@command -v gh >/dev/null || { echo "!!! gh not found — needed to mint GITHUB_TOKEN (https://cli.github.com)"; exit 1; }
	@gh auth status >/dev/null 2>&1 || { echo "!!! gh not authenticated — run 'gh auth login --scopes repo,read:org,project'"; exit 1; }
	@tmux new-session -d -s $(SESSION) -n $(SESSION) '$(LAUNCH)'
	@sleep 1
	@echo ">>> started session '$(SESSION)' — dashboard http://localhost:$(PORT) (make attach to see the TUI)"

down:
	@if tmux has-session -t $(SESSION) 2>/dev/null; then \
	  tmux send-keys -t $(SESSION) C-c 2>/dev/null || true; sleep 1; \
	  tmux kill-session -t $(SESSION) 2>/dev/null || true; \
	  echo ">>> stopped session '$(SESSION)'"; \
	else echo "'$(SESSION)' is not running"; fi

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
	@tmux attach -t $(SESSION)

doctor:
	@$(BIN) --config $(CONFIG) doctor
