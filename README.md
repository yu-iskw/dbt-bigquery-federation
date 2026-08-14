# dbt_bigquery_federation

`dbt_bigquery_federation` makes BigQuery `EXTERNAL_QUERY` practical from dbt by discovering remote schemas, planning type conversions, and rendering table expressions that compose with normal dbt models.

The primary UX is intentionally small:

```sql
select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

## Current provider scope

- `cloud_sql_postgres`
- `alloydb_postgres`

Both providers share the PostgreSQL metadata/dialect/type profile while remaining distinct provider identities. Spanner support is planned separately because its type semantics differ even for the PostgreSQL dialect.

## Configuration

```yaml
vars:
  dbt_bigquery_federation:
    metadata:
      mode: auto  # auto | live | pinned

    connections:
      application_pg:
        connection_id: "{{ env_var('BQ_APP_PG_CONNECTION_ID') }}"
        provider: cloud_sql_postgres
        defaults:
          schema: public
        types:
          policy: safe

      analytics_alloydb:
        connection_id: "{{ env_var('BQ_ALLOYDB_CONNECTION_ID') }}"
        provider: alloydb_postgres
        defaults:
          schema: public
```

`connection_id` must be fully qualified:

```text
projects/PROJECT_ID/locations/LOCATION/connections/CONNECTION_ID
```

## Metadata modes

### `auto` — recommended

Use a configured pin when one exists. Otherwise discover the current remote schema through `EXTERNAL_QUERY` and `information_schema.columns` during connected compilation.

```sql
{{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    table='orders',
    metadata_mode='auto'
) }}
```

### `live`

Always discover the current source schema and re-plan types.

```sql
{{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    table='orders',
    metadata_mode='live'
) }}
```

During parse-only evaluation (`execute=false`), the macro emits a passthrough `SELECT *` stub and performs no metadata I/O. Connected compilation replaces it with the discovered/type-planned query.

### `pinned`

Use Git-reviewed metadata under `vars.dbt_bigquery_federation.tables` and perform no live metadata lookup.

```yaml
vars:
  dbt_bigquery_federation:
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

This mode is useful for deterministic or regulated production workflows.

## Live schema discovery

Cloud SQL PostgreSQL and AlloyDB PostgreSQL use the same metadata profile. The package executes a remote query equivalent to:

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

through the configured BigQuery connection and normalizes the result before type planning.

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
      uuid:
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

This prints a `tables:` YAML fragment generated from live metadata. Users can review and commit it instead of manually copying large schemas.

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

By default, validation raises a compiler error when the live source differs from the configured pin.

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
    table='orders'
) }}
```

The same table expression can be used with `table`, `incremental`, or `ephemeral` models when the resulting SQL is valid. The package does not implement a custom materialization and does not set `on_schema_change` for incremental models.

## Operational notes

- BigQuery query processing location must be compatible with the connection location.
- Federation executes workload against the operational database; use read replicas/read pools where appropriate.
- Compiled dbt artifacts contain connection resource identifiers and remote relation names.
- Live discovery intentionally performs metadata I/O during connected compilation. Use `pinned` mode when compile-time external access is undesirable.
- The package manages neither BigQuery connection resources nor source credentials/IAM.

## Development

See [CONTRIBUTING.md](./CONTRIBUTING.md) for local tests and repository conventions. The architecture and roadmap are defined in [RFC-0001](./docs/rfcs/0001-bigquery-federation-architecture.md).
