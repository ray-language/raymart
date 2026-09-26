# raymart — common tasks. `make` lists them.

COMPOSE := docker compose
RAY_PROJECTS := libs/common $(wildcard services/*) $(wildcard libs/grpc) $(wildcard tools/*)

.DEFAULT_GOAL := help
.PHONY: help up down build ps logs test

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-12s %s\n", $$1, $$2}'

up: ## Build and start the whole system (gateway on :8088, dashboard on :8091)
	$(COMPOSE) up -d --build --wait

down: ## Stop the system (keeps the data volumes)
	$(COMPOSE) down

build: ## Build every image
	$(COMPOSE) build

ps: ## Container status
	$(COMPOSE) ps

logs: ## Follow the logs of every container
	$(COMPOSE) logs -f

test: ## Unit tests of every raylang project (no containers needed)
	@set -e; for p in $(RAY_PROJECTS); do echo "== $$p"; (cd $$p && ray test </dev/null); done
