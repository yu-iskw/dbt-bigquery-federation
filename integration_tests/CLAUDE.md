# Integration tests project

## Macro unit tests

- Mirror the package macro tree: for each path under [`macros/`](../macros/), place the corresponding test file under `macros/tests/` with the **same relative directories**, prefixed with `test_` on the basename.
  - Example: [`macros/federated_relation.sql`](../macros/federated_relation.sql) → `macros/tests/test_federated_relation.sql`
- **Exception:** the single entry macro for `dbt run-operation` stays at `macros/tests/test_macros.sql` (not nested). New suites are invoked from `test_macros()` there.

## Assertions and SQL

- Use [dbt-unittest](https://github.com/yu-iskw/dbt-unittest) (`dbt_unittest.*`) for assertions.
- Call package macros as `dbt_bigquery_federation.<macro>(...)`.
- Planner and renderer tests MUST assert SQL **strings**. Do not `run_query` `EXTERNAL_QUERY` (the test target is Postgres).

## Normalized column IR fixtures

Layer 2 (type planning / SQL generation) is tested offline via IR packs under [`macros/fixtures/ir/`](macros/fixtures/ir/). Those packs mirror e2e `type_matrix` tables and are consumed by [`macros/tests/federation/test_plan_from_ir.sql`](macros/tests/federation/test_plan_from_ir.sql) through `_federation_try_plan_columns`.

- Do **not** live-discover remote schemas in unit tests for the planner.
- Prefer `_ir_fixture_plan(fixture)` over hand-built connection/column stubs when a pack exists.
- Contract: [`docs/federation/normalized-column-ir.md`](../docs/federation/normalized-column-ir.md).

## Contributor details

See [`CONTRIBUTING.md`](../CONTRIBUTING.md) for setup (`make setup-integration-tests`) and full testing instructions.
