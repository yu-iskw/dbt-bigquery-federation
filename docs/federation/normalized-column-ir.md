# Normalized column IR

This document freezes the **schema between layer 1 (metadata extraction) and layer 2 (type planning / SQL generation)**.

```text
Layer 1  information_schema / pins
            │
            ▼
     normalized column IR   ← this contract
            │
            ▼
Layer 2  classify → decimal fold → remote SQL → EXTERNAL_QUERY
```

## Ownership

| Layer            | Responsibility                                                                        | Entry macros                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| 1. Extract       | Resolve connection, run provider metadata SQL (or load a pin), normalize rows into IR | `_federation_try_get_remote_columns`, `_federation_normalize_metadata_result`, `_federation_try_load_pin` |
| IR               | Serializable column list shared by live discovery, pins, and unit fixtures            | Documented below                                                                                          |
| 2. Plan + render | Classify types, fold decimals, build remote SQL, wrap `EXTERNAL_QUERY`                | `_federation_try_plan_columns`, `_federation_build_remote_sql`, `_federation_render_external_query`       |

Live and pinned frontends both call `_federation_try_plan_columns` with IR columns. Unit tests for layer 2 MUST pass IR fixtures into that macro and MUST NOT call `run_query` / live discovery.

Pins under `vars.dbt_bigquery_federation.tables` are a **serializable subset** of this IR (plus optional pin-only `strategy` / `remote_type` / `target_type` overrides). Do not invent a second column shape for planner fixtures.

## Required column fields

Each IR column is a mapping. Fields supplied by discovery when the provider exposes them:

| Field                      | Type           | Notes                                                                                      |
| -------------------------- | -------------- | ------------------------------------------------------------------------------------------ |
| `name`                     | string         | Required. Non-empty after trim.                                                            |
| `data_type`                | string         | Required. Provider-normalized bare type name (for example `numeric`, not `numeric(12,2)`). |
| `raw_data_type`            | string         | Optional. Unnormalized source type string.                                                 |
| `udt_name`                 | string \| null | Optional. Used when `data_type` is `USER-DEFINED` / `user-defined`.                        |
| `ordinal_position`         | int            | Optional for planning; required for pin/diff ordering when present.                        |
| `nullable`                 | bool           | Optional for planning.                                                                     |
| `precision`                | int \| null    | Required for decimal fold when `data_type` is `numeric` / `decimal`.                       |
| `scale`                    | int \| null    | Required for decimal fold when `data_type` is `numeric` / `decimal`.                       |
| `character_maximum_length` | int \| null    | Optional; used by schema diff for length-carrying types.                                   |

Pin-only optional fields (accepted by the planner via `_federation_lookup_override`):

| Field         | Type   | Notes                                           |
| ------------- | ------ | ----------------------------------------------- |
| `strategy`    | string | `remote_cast`, `passthrough`, or `fail`.        |
| `remote_type` | string | Remote cast target when `strategy=remote_cast`. |
| `target_type` | string | BigQuery target type hint.                      |

## Layer 2 call shape

```text
_federation_try_plan_columns(
  connection_cfg,   # provider, alias, connection_id, policy, query_execution_priority, …
  schema,           # remote schema (empty string for Spanner default)
  table,
  columns,          # list of IR column mappings
  type_policy=None,
  overrides=None,
  metadata_source='live' | 'pinned'
) → { ok, error, plan }
```

`plan.remote_sql` is the layer-2 product used by `federated_relation` and inspect. Renderer options (`decimal_option`, `query_execution_priority`) come from the plan + connection config.

## Fixture packs

Offline type-matrix fixtures live under [`integration_tests/macros/tests/fixtures/ir/`](../../integration_tests/macros/tests/fixtures/ir/). They return IR packs that mirror the e2e `type_matrix` tables so planner unit tests and live e2e assertions share one column contract without hitting BigQuery during `make run-unit-tests`.

See also RFC-0001 §10 (normalized schema model) and [`macros/CLAUDE.md`](../../macros/CLAUDE.md).
