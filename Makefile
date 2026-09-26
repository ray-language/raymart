# raymart — common tasks. `make` lists them.

COMPOSE := docker compose
RAY_PROJECTS := libs/common $(wildcard services/*) $(wildcard libs/grpc) $(wildcard tools/*)

.DEFAULT_GOAL := help

# The test stores' published ports; raykv and rayq have no healthcheck (their images hold only
# the binary), so `--wait` does not cover them: wait until every port accepts connections.
TEST_PORTS := 55432 53306 57017 57379 57450
WAIT_STORES = for port in $(TEST_PORTS); do i=0; until nc -z 127.0.0.1 $$port 2>/dev/null; do i=$$((i+1)); [ $$i -lt 60 ] || { echo "port $$port is not accepting connections" >&2; exit 1; }; sleep 0.5; done; done
.PHONY: help up down build ps logs test test-it check-release-it check-release cli e2e token chaos chaos-db trace log-stats bench bench-quick

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

test-it: ## Adapter integration tests against the stores in Docker (published on 127.0.0.1 high ports)
	$(COMPOSE) -f docker-compose.yml -f docker-compose.test.yml up -d --wait postgres mysql mongo raykv rayq
	@$(WAIT_STORES)
	@set -e; for p in $(wildcard services/*); do echo "== $$p"; (cd $$p && RAYMART_IT=1 ray test </dev/null); done

check-release-it: ## Integration tests with the RELEASE toolchain, from a container (stores via host.docker.internal)
	$(COMPOSE) -f docker-compose.yml -f docker-compose.test.yml up -d --wait postgres mysql mongo raykv rayq
	@$(WAIT_STORES)
	docker build -q -f docker/Dockerfile --target toolchain -t raymart-toolchain . >/dev/null
	@set -e; for p in $(wildcard services/*); do echo "== $$p"; docker run --rm -v "$$PWD":/src -w /src/$$p -e RAYMART_IT=1 -e RAYMART_IT_HOST=host.docker.internal raymart-toolchain sh -c 'ray fetch >/dev/null && ray test </dev/null'; done

check-release: ## Build + test every raylang project with the RELEASE toolchain the images use
	docker build -q -f docker/Dockerfile --target toolchain -t raymart-toolchain . >/dev/null
	@set -e; for p in $(RAY_PROJECTS); do echo "== $$p"; docker run --rm -v "$$PWD":/src -w /src/$$p raymart-toolchain sh -c 'ray fetch >/dev/null && ray test </dev/null'; done

# The raymart CLI (tools/raymart) as a native binary inside the compose network, like every
# other raymart program: no host toolchain needed.
CLI := $(COMPOSE) --progress quiet --profile bench run --rm -T --no-deps bench

cli: ## Build the raymart CLI image (e2e, token, chaos and bench use it)
	@$(COMPOSE) --progress quiet --profile bench build -q bench

e2e: cli ## End-to-end scenarios through the gateway (needs `make up`)
	@$(CLI) e2e http://raygate:8080

token: cli ## A development JWT: make token USER_ID=ada
	@$(CLI) token $(or $(USER_ID),$(USER))

chaos: cli ## Resilience: checkout while payment is down; the order is paid once it is back
	@set -e; user=chaos-$$$$; \
	$(COMPOSE) stop payment >/dev/null; \
	id=$$($(CLI) order $$user 5 1 4242); echo "order $$id placed while payment is down"; \
	sleep 4; echo "after 4 s: $$($(CLI) status $$user $$id)"; \
	$(COMPOSE) start payment >/dev/null; echo "payment is back"; \
	for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do s=$$($(CLI) status $$user $$id); [ "$$s" = "paid" ] && break; sleep 1; done; \
	echo "after the restart: $$s"; [ "$$s" = "paid" ]

chaos-db: cli ## Resilience: restart every datastore; the first e2e run afterwards must pass whole
	@$(COMPOSE) restart postgres mysql mongo raykv >/dev/null
	@$(COMPOSE) up -d --wait postgres mysql mongo raykv >/dev/null 2>&1
	@echo "datastores restarted: the services' pooled connections are all stale"
	@$(CLI) e2e http://raygate:8080

trace: ## Follow one request across every service: make trace ID=<32-hex trace id>
	@$(COMPOSE) logs --no-log-prefix products cart orders payment 2>/dev/null | grep '^{' \
		| $(COMPOSE) --profile tools run --rm -T raylogs --json --filter 'trace_id=$(ID)' --output json

log-stats: ## Log lines per service and level (raylogs)
	@$(COMPOSE) logs --no-log-prefix products cart orders payment 2>/dev/null | grep '^{' \
		| $(COMPOSE) --profile tools run --rm -T raylogs --json --count-by service

bench: ## Load test: a ramp of 1→8→32→64 VUs × 15 s per scenario, invariants, report in perf/results/
	@scripts/bench.sh $(ARGS)

bench-quick: ## A short bench (1 and 16 VUs × 5 s) to check that everything works
	@scripts/bench.sh --stages 1,16 --duration 5 --drain-stock 100
