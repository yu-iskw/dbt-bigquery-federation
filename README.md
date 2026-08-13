# dbt_bigquery_federation

**`dbt_bigquery_federation`** is a dbt package that turns BigQuery `EXTERNAL_QUERY` into a pinned, schema-aware table-expression primitive.

Add it as a dependency, run `dbt deps`, and call macros from the `dbt_bigquery_federation` namespace.

If you maintain this repository, see [CONTRIBUTING.md](./CONTRIBUTING.md) for tests, linting, and development layout. Architecture: [docs/rfcs/0001-bigquery-federation-architecture.md](./docs/rfcs/0001-bigquery-federation-architecture.md).

## Installation

In your **root** dbt project, add a [package](https://docs.getdbt.com/docs/build/packages) entry:

```yaml
packages:
  - git: "https://github.com/YOUR_ORG/YOUR_REPO.git"
    revision: main # or a tag / SHA
```

Then run:

```bash
dbt deps
```

## Requirements

- **dbt Core** **1.10 or newer, below 3.0** (see `require-dbt-version` in [`dbt_project.yml`](./dbt_project.yml)).
- A **BigQuery** target in the consuming project. This package emits BigQuery `EXTERNAL_QUERY` SQL.
- A BigQuery connection resource to Cloud SQL PostgreSQL. The package does not create connections, IAM, or database users.

Supported CI in this repository uses **Postgres as a Jinja test engine** (no GCP). Fusion BigQuery is Preview and is **not** advertised as supported.

## What is in this package

- **`federated_relation`** — plans types from Git-reviewed pins and renders `EXTERNAL_QUERY`.
- **`external_query`** — trusted raw remote SQL hatch (no planner).
- **`federation_inspect`** — `run-operation` that prints the conversion plan for a pin.

Pins live in `vars`. Compilation does **not** call `run_query`. The same Git SHA plus the same vars compiles the same SQL.

## Configuration

```yaml
vars:
  dbt_bigquery_federation:
    connections:
      application_pg:
        connection_id: "{{ env_var('BQ_FEDERATION_CONNECTION_ID') }}"
        provider: cloud_sql_postgres
        defaults:
          schema: public
        types:
          policy: safe   # safe | strict
    tables:
      application_pg.public.orders:
        columns:
          - name: id
            data_type: bigint
          - name: user_uuid
            data_type: uuid
          - name: amount
            data_type: numeric
            precision: 12
            scale: 2
```

`connection_id` must be fully qualified:

```text
projects/PROJECT_ID/locations/LOCATION/connections/CONNECTION_ID
```

v0.1 provider: `cloud_sql_postgres` only.

## Macros

### `federated_relation`

Returns a **SQL table expression**. Plan types from the pin; preserve remote `SELECT * FROM T` when every column is natively safe.

```sql
select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

To return fewer columns **without** disabling BigQuery federated pushdown, project on the BigQuery side:

```sql
select id, amount
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

SQL pushdowns apply only to federated queries of the form `SELECT * FROM T`. The package emits a remote column list only when a conversion (for example `uuid` → `text`) requires it.

Under **`safe`** (default), known-unsupported PostgreSQL types such as `uuid` and `jsonb` are remote-cast to `text`. Unknown types fail. **`strict`** fails unsupported types until you pass an override.

Incremental models should set `on_schema_change='fail'` unless you explicitly choose another strategy. This package does not set it for you.

### `external_query`

Trusted raw remote SQL. The dbt identity executes this string on the remote database.

```sql
select *
from {{ dbt_bigquery_federation.external_query(
    connection='application_pg',
    sql='select id, created_at from public.orders'
) }}
```

### `federation_inspect`

```bash
dbt run-operation federation_inspect --args '{connection: application_pg, schema: public, table: orders}'
```

Prints provider, policy, body class, decimal option, and per-column action/lossiness/`pushdown=kept|lost`. `live=true` is rejected in v0.1.

## Operational notes

- Compiled SQL includes connection resource IDs and remote relation names. Treat `target/`, logs, and CI artifacts accordingly.
- The package cannot enforce a read-only Cloud SQL user.
- A Cloud SQL table is not a BigQuery `source()`. Wrap `federated_relation` in a staging model and `ref()` that model in the rest of the DAG.

For **overriding** dispatched macros and how **dbt docs** surfaces macro metadata, see [CONTRIBUTING.md — Downstream projects: overrides and dbt docs](./CONTRIBUTING.md#downstream-projects-overrides-and-dbt-docs).
