.PHONY: setup clean test \
	postgres-up postgres-wait postgres-down postgres-logs \
	dialect-up dialect-down dialect-logs \
	run-unit-tests run-unit-tests-postgres \
	run-integration-tests run-integration-tests-postgres \
	run-dialect-extract-tests \
	run-unit-tests-fusion run-integration-tests-fusion run-fusion-tests

# Nox 2026+ errors if both NO_COLOR and FORCE_COLOR are set (common in IDEs/CI).
UV_RUN_NOX = env -u NO_COLOR -u FORCE_COLOR -u CLICOLOR_FORCE uv run nox
UV_RUN_NOX_FUSION = $(UV_RUN_NOX) -f noxfile_fusion.py

# Nox session names (quoted for bash -lc recipes).
NOX_UNIT_PG_110 := unit_tests-3.12(adapter='postgres', uv_group='dbt-core-1-10')
NOX_UNIT_PG_111 := unit_tests-3.12(adapter='postgres', uv_group='dbt-core-1-11')
NOX_UNIT_PG_112 := unit_tests-3.12(adapter='postgres', uv_group='dbt-core-1-12')
NOX_INT_PG_110 := integration_tests-3.12(adapter='postgres', uv_group='dbt-core-1-10')
NOX_INT_PG_111 := integration_tests-3.12(adapter='postgres', uv_group='dbt-core-1-11')
NOX_INT_PG_112 := integration_tests-3.12(adapter='postgres', uv_group='dbt-core-1-12')
NOX_DIALECT := dialect_extract_tests

setup:
	uv sync

clean:
	rm -rf target logs dbt_packages

postgres-up:
	docker compose -f docker-compose.postgres.yml up -d postgres

postgres-wait:
	@started_at="$$(date +%s)"; \
	while true; do \
		state="$$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' dbt-bigquery-federation-postgres 2>/dev/null || true)"; \
		if [ "$$state" = "healthy" ]; then \
			exit 0; \
		fi; \
		if [ -z "$$state" ]; then \
			echo "Postgres container dbt-bigquery-federation-postgres was not created successfully." >&2; \
			exit 1; \
		fi; \
		if [ $$(( $$(date +%s) - $$started_at )) -ge 60 ]; then \
			echo "Timed out waiting for Postgres to become healthy." >&2; \
			exit 1; \
		fi; \
		sleep 1; \
	done

postgres-down:
	docker compose -f docker-compose.postgres.yml down --remove-orphans

postgres-logs:
	docker compose -f docker-compose.postgres.yml logs --no-color postgres

dialect-up:
	docker compose -p dbt-bigquery-federation-dialect -f docker-compose.dialect.yml up -d dialect-postgres spanner-emulator

dialect-down:
	docker compose -p dbt-bigquery-federation-dialect -f docker-compose.dialect.yml down

dialect-logs:
	docker compose -p dbt-bigquery-federation-dialect -f docker-compose.dialect.yml logs --no-color dialect-postgres spanner-emulator

run-unit-tests-postgres:
	./scripts/run_with_postgres_container.sh \
		bash -lc "$(UV_RUN_NOX) -s \"$(NOX_UNIT_PG_110)\" && $(UV_RUN_NOX) -s \"$(NOX_UNIT_PG_111)\" && $(UV_RUN_NOX) -s \"$(NOX_UNIT_PG_112)\""

run-unit-tests: clean run-unit-tests-postgres

run-unit-tests-fusion: clean
	./scripts/run_with_postgres_container.sh \
		$(UV_RUN_NOX_FUSION) -s fusion_unit_tests

run-integration-tests-postgres:
	./scripts/run_with_postgres_container.sh \
		bash -lc "$(UV_RUN_NOX) -s \"$(NOX_INT_PG_110)\" && $(UV_RUN_NOX) -s \"$(NOX_INT_PG_111)\" && $(UV_RUN_NOX) -s \"$(NOX_INT_PG_112)\""

run-integration-tests: clean run-integration-tests-postgres

run-integration-tests-fusion: clean
	./scripts/run_with_postgres_container.sh \
		$(UV_RUN_NOX_FUSION) -s fusion_integration_tests

run-fusion-tests: run-unit-tests-fusion run-integration-tests-fusion

# Layer 3: dialect Postgres + Spanner emulator only (dbt export uses duckdb target).
run-dialect-extract-tests: clean
	./scripts/run_with_dialect_containers.sh \
		bash -lc "$(UV_RUN_NOX) -s \"$(NOX_DIALECT)\""

test: run-unit-tests run-integration-tests
