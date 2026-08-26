# dbt_bigquery_federation

`dbt_bigquery_federation` makes BigQuery `EXTERNAL_QUERY` practical from dbt by
planning type conversions from a Git-reviewed schema pin and rendering table
expressions that compose with normal dbt models.

The primary UX is intentionally small:

```sql
select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

`federated_relation` is **artifact-first**: it always plans from
`vars.dbt_bigquery_federation.tables` and never calls `run_query`. Live
`information_schema` discovery happens only in `run-operation` helpers.

## Current provider scope

- `cloud_sql_postgres`
- `alloydb_postgres`
- `spanner_google_sql`

Cloud SQL PostgreSQL and AlloyDB PostgreSQL share the PostgreSQL metadata/dialect/type profile while remaining distinct provider identities. Spanner GoogleSQL has a separate metadata/type profile because its federation semantics differ. Spanner external datasets are intentionally out of scope.

## Configuration

```yaml
vars:
  dbt_bigquery_federation:
    connections:
      application_pg:
        connection_id: "{{ env_var('BQ_APP_PG_CONNECTION_ID') }}"
        provider: cloud_sql_postgres
        types:
          policy: safe

      analytics_alloydb:
        connection_id: "{{ env_var('BQ_ALLOYDB_CONNECTION_ID') }}"
        provider: alloydb_postgres

      spanner_app:
        # The data connection may enable Spanner parallel reads.
        connection_id: "{{ env_var('BQ_SPANNER_CONNECTION_ID') }}"
        # Recommended when the data connection is parallel: use a separate
        # non-parallel connection for INFORMATION_SCHEMA discovery.
        metadata_connection_id: "{{ env_var('BQ_SPANNER_METADATA_CONNECTION_ID') }}"
        provider: spanner_google_sql

    tables:
      application_pg.public.orders:
        columns:
          - name: id
            data_type: bigint
          - name: amount
            data_type: numeric
            precision: 12
            scale: 2
```

On **dbt Core 1.12+**, the same mapping can live in a root [`vars.yml`](https://docs.getdbt.com/docs/build/project-variables) file (still accessed via `var()`). This package requires `>=1.10.0` and continues to read `vars.dbt_bigquery_federation`.

`schema` is required on every federation call site. Pass the remote schema name (for example `public` on PostgreSQL/AlloyDB). For Spanner GoogleSQL's default schema, pass `schema=''` (empty string), matching Spanner `INFORMATION_SCHEMA` where the default schema is empty.

Do not set `connections.*.defaults`; that key is rejected.

`connection_id` and, when configured, `metadata_connection_id` must be fully qualified:

```text
projects/PROJECT_ID/locations/LOCATION/connections/CONNECTION_ID
```

`metadata_connection_id` is optional and defaults to `connection_id`. Normal federated data queries always use `connection_id`; live metadata discovery (operations only) uses `metadata_connection_id`.

For Spanner specifically, a parallel BigQuery connection can only execute queries that satisfy Spanner's partitionability requirements. `INFORMATION_SCHEMA` queries are not guaranteed to be root partitionable, so use a dedicated non-parallel metadata connection when the primary data connection enables parallel reads. A single non-parallel connection remains sufficient when parallel reads aren't needed.

## Why pins are required in models

dbt's [`execute`](https://docs.getdbt.com/reference/dbt-jinja-functions/execute) flag is `False` only during parse. [`run_query`](https://docs.getdbt.com/reference/dbt-jinja-functions/run_query) still runs whenever dbt compiles with a warehouse connection — including `dbt compile`, `dbt run`, `dbt build`, and `dbt docs generate` (unless `--no-compile`). Guarding with `{% if execute %}` does **not** skip discovery on compile/docs.

A Hub package also has no filesystem read API for arbitrary YAML paths, and [`graph`](https://docs.getdbt.com/reference/dbt-jinja-functions/graph) is incomplete during parse, so `sources.yml` cannot be the IR store for `federated_relation`. Parse-safe IR is therefore `var()` — typically under `vars.dbt_bigquery_federation.tables`.

Progressive governance is: inspect/generate a pin via operations, commit it, then compile models from that artifact. Passing `metadata_mode='live'` or `'auto'` to `federated_relation` raises a compiler error. The former package key `vars.dbt_bigquery_federation.metadata` is also rejected — remove it from project config.

## Getting started

1. Configure a connection under `vars.dbt_bigquery_federation.connections`.
2. Generate a pin:

```bash
dbt run-operation federation_generate_pin \
  --args '{connection: application_pg, schema: public, table: orders}'
```

3. Paste the printed `tables:` fragment into `dbt_project.yml` or `vars.yml` and commit.
4. Call `federated_relation` from a model.

Remote SQL lists the pinned columns instead of `SELECT *`, so newly added source columns do not appear until the pin is updated.

## Live schema discovery (operations)

Cloud SQL PostgreSQL and AlloyDB PostgreSQL use the same metadata profile. Operations execute a remote query equivalent to:

```sql
select
  column_name,
  data_type,
  udt_name,
  ordinal_position,
  is_nullable,
  numeric_precision,
  numeric_scale,
  character_maximum_length
from information_schema.columns
where table_schema = 'public'
  and table_name = 'orders'
order by ordinal_position
```

through the configured BigQuery metadata connection and normalize the result before type planning.

Spanner GoogleSQL uses its own `INFORMATION_SCHEMA.COLUMNS` query and reads `SPANNER_TYPE`. See [Spanner GoogleSQL federation](./docs/providers/spanner-google-sql.md) for the parallel-read connection guidance.

You can call discovery directly:

```bash
dbt run-operation get_remote_columns \
  --args '{connection: application_pg, schema: public, table: orders}'
```

## Type planning

The planner prefers native BigQuery federation mappings. Under `safe`, known unsupported PostgreSQL types such as `uuid` and `jsonb` are remote-cast to `text`; unknown types fail rather than being guessed. Under `strict`, unsupported types also fail unless explicitly overridden.

```yaml
vars:
  dbt_bigquery_federation:
    type_overrides:
      money:
        strategy: remote_cast
        remote_type: text
        target_type: STRING
```

The planner also folds relation-level PostgreSQL `numeric` requirements so that `EXTERNAL_QUERY` can use the query-wide `default_type_for_decimal_columns` option where appropriate.

## Inspection and governance workflow

### Inspect the live source

```bash
dbt run-operation federation_inspect \
  --args '{connection: application_pg, schema: public, table: orders, live: true}'
```

The report includes provider, metadata source, policy, plan shape, decimal option, pushdown status, and per-column conversion actions.

### Generate a pin

```bash
dbt run-operation federation_generate_pin \
  --args '{connection: application_pg, schema: public, table: orders}'
```

This prints a `tables:` YAML fragment generated from live metadata. Users can review and commit it instead of manually copying large schemas. dbt operations cannot write project files.

### Compare a pin with the live source

```bash
dbt run-operation federation_schema_diff \
  --args '{connection: application_pg, schema: public, table: orders}'
```

The operation reports added, removed, and changed columns.

### Validate schema drift in CI

```bash
dbt run-operation federation_validate \
  --args '{connection: application_pg, schema: public, table: orders}'
```

By default, validation raises a compiler error when the live source differs from the configured pin. Comparison ignores PostgreSQL `information_schema` bit-widths on integers and floats (`bigint` is not `bigint(64,0)`), normalizes pin type aliases such as `timestamp` and `varchar`, and treats `numeric` precision/scale plus character `character_maximum_length` as part of the type.

## Raw escape hatch

`external_query` bypasses metadata discovery, type planning, pin validation, and identifier construction. Treat its SQL argument as trusted remote SQL.

```sql
select *
from {{ dbt_bigquery_federation.external_query(
    connection='application_pg',
    sql='select id, created_at from public.orders'
) }}
```

## dbt materializations

Federation remains a source-access concern. Use normal dbt persistence:

```sql
{{ config(materialized='view') }}

select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

The same table expression can be used with `table`, `incremental`, or `ephemeral` models when the resulting SQL is valid. The package does not implement a custom materialization and does not set `on_schema_change` for incremental models.

## Operational notes

- BigQuery query processing location must be compatible with the connection location.
- Federation executes workload against the operational database; use read replicas/read pools where appropriate.
- Spanner parallel connections are appropriate only for partitionable queries. Use `metadata_connection_id` with a non-parallel Spanner connection for reliable live metadata discovery when the data connection is parallel.
- Compiled dbt artifacts contain connection resource identifiers and remote relation names.
- Models never perform metadata I/O. Use operations when compile-time external access is required for inspect/generate/validate.
- The package manages neither BigQuery connection resources nor source credentials/IAM.

## Development

See [CONTRIBUTING.md](./CONTRIBUTING.md) for local tests and repository conventions. The architecture and roadmap are defined in [RFC-0001](./docs/rfcs/0001-bigquery-federation-architecture.md). The [normalized column IR](./docs/federation/normalized-column-ir.md) is the contract between remote metadata extraction and SQL planning.
