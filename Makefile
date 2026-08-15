lint:
	uv run --group dev pre-commit run -a

update-pre-commit-hooks:
	uv run --group dev pre-commit autoupdate

######################################################################
# Integration tests
######################################################################
setup-integration-tests:
	$(MAKE) -C integration_tests setup

run-unit-tests:
	$(MAKE) -C integration_tests run-unit-tests

run-unit-tests-fusion:
	$(MAKE) -C integration_tests run-unit-tests-fusion

run-integration-tests:
	$(MAKE) -C integration_tests run-integration-tests

run-integration-tests-fusion:
	$(MAKE) -C integration_tests run-integration-tests-fusion

run-fusion-tests:
	$(MAKE) -C integration_tests run-fusion-tests

test-integration:
	$(MAKE) -C integration_tests run-integration-tests

.PHONY: test-all
test-all:
	integration_tests/scripts/run_with_postgres_container.sh \
		./scripts/run_with_bigquery_emulator.sh \
		uv run bash ../dev/test_all.sh

test: run-unit-tests run-integration-tests
