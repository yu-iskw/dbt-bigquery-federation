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

run-dialect-extract-tests:
	$(MAKE) -C integration_tests run-dialect-extract-tests

run-fusion-tests:
	$(MAKE) -C integration_tests run-fusion-tests

test-integration:
	$(MAKE) -C integration_tests run-integration-tests

test: run-unit-tests run-integration-tests
