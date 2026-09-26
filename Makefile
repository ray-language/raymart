# raymart — common tasks. `make` lists them.

COMPOSE := docker compose
RAY_PROJECTS := libs/common $(wildcard services/*) $(wildcard libs/grpc) $(wildcard tools/*)

.DEFAULT_GOAL := help
.PHONY: help up down build ps logs test test-it check-release e2e token chaos trace log-stats

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
	@set -e; for p in $(wildcard services/*); do echo "== $$p"; (cd $$p && RAYMART_IT=1 ray test </dev/null); done

check-release: ## Build + test every raylang project with the RELEASE toolchain the images use
	docker build -q -f docker/Dockerfile --target toolchain -t raymart-toolchain . >/dev/null
	@set -e; for p in $(RAY_PROJECTS); do echo "== $$p"; docker run --rm -v "$$PWD":/src -w /src/$$p raymart-toolchain sh -c 'ray fetch >/dev/null && ray test </dev/null'; done

e2e: ## End-to-end scenarios through the gateway (needs `make up`)
	cd tools/raymart && ray run -- e2e http://127.0.0.1:8088

token: ## A development JWT: make token USER_ID=ada
	@cd tools/raymart && ray run -- token $(or $(USER_ID),$(USER))

chaos: ## Resilience: checkout while payment is down; the order is paid once it is back
	@set -e; cd tools/raymart; \
	user=chaos-$$$$; \
	(cd ../.. && $(COMPOSE) stop payment >/dev/null); \
	id=$$(ray run -- order $$user 5 1 4242); echo "order $$id placed while payment is down"; \
	sleep 4; echo "after 4 s: $$(ray run -- status $$user $$id)"; \
	(cd ../.. && $(COMPOSE) start payment >/dev/null); echo "payment is back"; \
	for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do s=$$(ray run -- status $$user $$id); [ "$$s" = "paid" ] && break; sleep 1; done; \
	echo "after the restart: $$s"; [ "$$s" = "paid" ]

trace: ## Follow one request across every service: make trace ID=<32-hex trace id>
	@$(COMPOSE) logs --no-log-prefix products cart orders payment 2>/dev/null | grep '^{' \
		| $(COMPOSE) --profile tools run --rm -T raylogs --json --filter 'trace_id=$(ID)' --output json

log-stats: ## Log lines per service and level (raylogs)
	@$(COMPOSE) logs --no-log-prefix products cart orders payment 2>/dev/null | grep '^{' \
		| $(COMPOSE) --profile tools run --rm -T raylogs --json --count-by service
