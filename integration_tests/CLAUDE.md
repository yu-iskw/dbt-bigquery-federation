# Integration tests project

## Macro unit tests

- Mirror the package macro tree: for each path under [`macros/`](../macros/), place the corresponding test file under `macros/tests/` with the **same relative directories**, prefixed with `test_` on the basename.
  - Example: [`macros/federated_relation.sql`](../macros/federated_relation.sql) → `macros/tests/test_federated_relation.sql`
- **Exception:** the single entry macro for `dbt run-operation` stays at `macros/tests/test_macros.sql` (not nested). New suites are invoked from `test_macros()` there.

## Assertions and SQL

- Use [dbt-unittest](https://github.com/yu-iskw/dbt-unittest) (`dbt_unittest.*`) for assertions.
- Call package macros as `dbt_bigquery_federation.<macro>(...)`.
- Planner and renderer tests MUST assert SQL **strings**. Do not `run_query` `EXTERNAL_QUERY` (the test target is Postgres).

## Contributor details

See [`CONTRIBUTING.md`](../CONTRIBUTING.md) for setup (`make setup-integration-tests`) and full testing instructions.
