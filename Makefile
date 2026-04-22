.PHONY: lint test test-fixture fixtures clean help

FIXTURE := tests/fixtures/sample_operator_e2e

## Quality

lint: ## yamllint action.yml + workflows + fixtures (dockerized, no host install)
	docker run --rm -v $$(pwd):/data cytopia/yamllint -d relaxed action.yml .github/workflows/ tests/

## Testing

test: test-fixture ## Run the fixture e2e test locally (requires kind + docker + Go + kubectl)

test-fixture: ## Run `make test-e2e` inside the fixture operator (assumes a kind cluster is already running)
	cd $(FIXTURE) && make test-e2e

## Fixtures

fixtures: ## List fixture files (committed — nothing to generate)
	@ls -R $(FIXTURE)

## Cleanup

clean: ## Remove Go test caches from the fixture
	cd $(FIXTURE) && go clean -testcache ./... || true

## Help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
