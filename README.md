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
    type_overrides:
      uuid:
        strategy: remote_cast
        remote_type: text
        target_type: STRING
```

`connection_id` must be fully qualified:

```text
projects/PROJECT_ID/locations/LOCATION/connections/CONNECTION_ID
```

Different dbt targets may use different environment variables or target-scoped vars for `connection_id`. Do not treat one production connection resource as the only configuration.

v0.1 provider: `cloud_sql_postgres` only.

Override precedence (later entries win):

1. package defaults
2. connection `types.policy`
3. `type_overrides` by source type
4. pin column `strategy` / `remote_type` / `target_type`
5. invocation `type_policy` / `overrides`

## Macros

### `federated_relation`

Returns a **SQL table expression**. Plan types from the pin; preserve remote `SELECT * FROM T` when every column is natively safe.

Remote schema and table identifiers are **always** PostgreSQL-quoted (double quotes; internal `"` doubled). There is no unquoted-if-safe path.

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

SQL pushdowns apply only to federated queries of the form `SELECT * FROM T`. When that shape survives, BigQuery may prune columns and push filters; filter literals are limited to the Google-listed types, not `NUMERIC` / `BIGNUMERIC` / `TIME` / `BYTES`. The package emits a remote column list only when a conversion (for example `uuid` → `text`) requires it.

Under **`safe`** (default), known-unsupported PostgreSQL types such as `uuid`, `jsonb`, `pg_lsn`, `tsquery`, `tsvector`, and `txid_snapshot` are remote-cast to `text`. Unknown types, including arrays, fail. **`strict`** fails unsupported types until you pass an override. Compile warns when a safe decimal fold remote-casts oversized or unbounded decimals and loses pushdown.

Type mapping notes:

- `bit`, `bit varying`, and alias `varbit` map natively to BigQuery `BYTES`.
- `json` maps natively to BigQuery `STRING` (`jsonb` is unsupported).
- Arrays are unknown (not in Google's Cloud SQL `EXTERNAL_QUERY` map).

Decimal options: omitted `EXTERNAL_QUERY` options JSON means Google's default `NUMERIC`. The package never emits `"numeric"`. It emits `"bignumeric"` when **any** remaining native decimal needs `BIGNUMERIC`, including a mix with NUMERIC-fit siblings after unbounded offenders are remote-cast. Widening NUMERIC-range values to `BIGNUMERIC` stays exact.

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

Optional `type_policy` and `overrides` follow `live` so inspect can mirror a `federated_relation` invocation. Positional `true` still means `live`.

```bash
dbt run-operation federation_inspect --args '{connection: application_pg, schema: public, table: orders, type_policy: strict}'
```

## Operational notes

- **Locations.** The BigQuery query processing location should match the location in the connection resource ID. v0.1 does not fail compile on a mismatch; align locations in GCP.
- **Quotas.** A federated query may use at most 10 unique connections. Cross-region federated queries consume a bytes quota. `maximum bytes billed` is not supported for federated queries. Isolate Cloud SQL from this workload with a read replica.
- **Credentials.** The package stores connection IDs only and cannot enforce a read-only Cloud SQL user.
- **Compiled artifacts.** Compiled SQL includes connection resource IDs and remote relation names. Treat `target/`, logs, and CI artifacts accordingly.
- **Precedence.** Policy and conversion overrides follow the ladder in [Configuration](#configuration): package defaults, then connection `types.policy`, then `type_overrides`, then pin column fields, then invocation `type_policy` / `overrides`.
- A Cloud SQL table is not a BigQuery `source()`. Wrap `federated_relation` in a staging model and `ref()` that model in the rest of the DAG.

For **overriding** dispatched macros and how **dbt docs** surfaces macro metadata, see [CONTRIBUTING.md — Downstream projects: overrides and dbt docs](./CONTRIBUTING.md#downstream-projects-overrides-and-dbt-docs).
