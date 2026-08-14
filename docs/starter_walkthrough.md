# Package walkthrough

This package ships pinned BigQuery `EXTERNAL_QUERY` macros and a GCP-free test harness.

## Public macros

- `macros/federated_relation.sql` — table-expression planner
- `macros/external_query.sql` — trusted raw SQL hatch
- `macros/federation/inspect.sql` — `federation_inspect`

Internals live under `macros/federation/`. See [`macros/CLAUDE.md`](../macros/CLAUDE.md) and [RFC-0001](rfcs/0001-bigquery-federation-architecture.md).

## Unit tests

Macro unit tests live under `integration_tests/macros/tests/`, **mirroring** the package macro tree. The `dbt run-operation` entry macro stays at `integration_tests/macros/tests/test_macros.sql`.

The test runner:

1. installs the local package via `packages.yml`
2. runs `dbt deps`
3. executes `dbt run-operation test_macros`

Planner tests assert rendered SQL strings. They do not execute `EXTERNAL_QUERY`.

## Integration tests

Non-federated smoke: seed `integration_tests/data/raw_users.csv` and model `integration_tests/models/example/stg_users.sql` (`dbt build --exclude federation`).

Federated compile smoke: `integration_tests/models/federation/stg_federated_orders.sql` (`dbt compile --select federation`).

```bash
make setup-integration-tests
make run-unit-tests
make run-integration-tests
```

The required suite executes on:

- `postgres` (Jinja engine)
