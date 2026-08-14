# Integration tests for `dbt_bigquery_federation`

This directory contains the test harness:

- a required dbt-core lane on `postgres` (Jinja engine) for `dbt-core-1-10` and `dbt-core-1-11`
- a non-blocking `dbt Fusion` preview lane on the same Postgres contract

Planner tests do not require GCP. `dbt build` runs the non-federated example models; `dbt compile` checks the federated staging model.

## Setup

```bash
uv sync
```

## Postgres

Local Postgres-backed tests use Docker Compose automatically. The repo starts and tears down a temporary Postgres container for the Postgres test phase.

Prerequisite:

```bash
docker compose version
```

The default profile values are:

- host: `localhost`
- port: `5432`
- user: `postgres`
- password: `postgres`
- database: `dbt_package_template`
- schema: `dbt_package_template`

## Commands

```bash
make run-unit-tests
make run-integration-tests
make run-unit-tests-fusion
make run-integration-tests-fusion
```

Useful helper commands:

```bash
make -C integration_tests postgres-up
make -C integration_tests postgres-down
make -C integration_tests postgres-logs
```

The unit-test harness runs `dbt run-operation test_macros`.
Macro test files mirror `macros/` under `macros/tests/`.
The integration harness runs `dbt build --exclude federation` then `dbt compile --select federation`.

## Fusion lane

Fusion sessions live in [`noxfile_fusion.py`](noxfile_fusion.py) (not the default `noxfile.py` entrypoint). Run them with `uv run nox -f noxfile_fusion.py` (the Makefile fusion targets pass `-f` for you). Fusion CI is **non-blocking**. Fusion preview treats postgres as experimental; the harness sets `DBT_ALLOW_EXPERIMENTAL_ADAPTERS=true` so the Jinja engine can load.

Set `DBT_FUSION_VERSION` if you need to pin a specific Fusion build instead of the latest available installer target.
