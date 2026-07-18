# The human interface to the platform. `make up` needs only docker + make.
# Node is required only by `deploy` (nx); raw fallbacks are in docs/user-guide.md.

COMPOSE := docker compose
SERVICE ?=
N ?= 2

.PHONY: up down reset logs dev build deploy rollback scale load load-stop demo-failure

# Run one app on the host with hot reload (needs `make up` for postgres).
dev:
	@test -n "$(SERVICE)" || (echo "usage: make dev SERVICE=api|worker|dashboard" && exit 1)
	npx nx run $(SERVICE):dev

# Build all app images (or one: make build SERVICE=api).
build:
	npx nx run-many -t build $(if $(SERVICE),-p $(SERVICE),)

# Foreground by default: log streams from every service in this terminal
# (Ctrl-C stops the stack). `make up D=1` detaches instead.
up:
	@echo ""
	@echo "  dashboard  http://localhost:8080"
	@echo "  grafana    http://localhost:3000   (Pulse Ops dashboard, no login)"
	@echo "  api        http://localhost:8000/docs"
	@echo ""
	$(COMPOSE) up --build $(if $(D),-d,)

down:
	$(COMPOSE) down

reset:
	$(COMPOSE) down -v

logs:
	@echo ">> tip: Grafana (localhost:3000) has searchable logs for all services"
	$(COMPOSE) logs -f --tail=100

# Build a versioned image, repoint its tag in .env, recreate only that service.
deploy:
	@test -n "$(SERVICE)" || (echo "usage: make deploy SERVICE=api|worker|dashboard" && exit 1)
	@TAG=$$(git rev-parse --short HEAD 2>/dev/null || date +%s); \
	VAR=$$(echo $(SERVICE) | tr a-z A-Z)_TAG; \
	echo ">> building pulse-$(SERVICE):$$TAG"; \
	TAG=$$TAG npx nx run $(SERVICE):build; \
	grep -v "^$$VAR=" .env > .env.tmp && echo "$$VAR=$$TAG" >> .env.tmp && mv .env.tmp .env; \
	echo ">> repointed $$VAR=$$TAG"; \
	$(COMPOSE) up -d $(SERVICE)

# Repoint to an existing image tag (docker images pulse-<service> lists them).
rollback:
	@test -n "$(SERVICE)" -a -n "$(TAG)" || (echo "usage: make rollback SERVICE=api TAG=abc123" && exit 1)
	@VAR=$$(echo $(SERVICE) | tr a-z A-Z)_TAG; \
	grep -v "^$$VAR=" .env > .env.tmp && echo "$$VAR=$(TAG)" >> .env.tmp && mv .env.tmp .env; \
	echo ">> repointed $$VAR=$(TAG)"; \
	$(COMPOSE) up -d $(SERVICE)

scale:
	$(COMPOSE) up -d --scale worker=$(N) --no-recreate worker

load:
	@nohup sh ops/loadgen/loadgen.sh > /dev/null 2>&1 & echo $$! > .load.pid
	@echo ">> load running (pid $$(cat .load.pid)) — make load-stop to end"

load-stop:
	@kill $$(cat .load.pid) 2>/dev/null && rm -f .load.pid && echo ">> load stopped" || echo ">> no load running"

# Guided worker-outage drill — the runbook scenario.
demo-failure:
	@$(MAKE) load
	@echo ">> traffic flowing. stopping worker in 5s — watch queue depth climb in Grafana"; sleep 5
	$(COMPOSE) stop worker
	@printf ">> worker down, events buffering durably. press enter to recover... "; read _
	$(COMPOSE) start worker
	@echo ">> worker recovering — watch queue depth drain to 0. make load-stop when done."
