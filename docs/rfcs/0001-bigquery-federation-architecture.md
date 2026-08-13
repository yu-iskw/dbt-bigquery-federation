# RFC-0001: BigQuery Federation Compiler for dbt v1 and v2

- **Status:** Proposed
- **Date:** 2026-08-14
- **Package namespace:** `dbt_bigquery_federation`
- **Target:** BigQuery
- **dbt compatibility objective:** `>=1.10.0,<3.0.0`
- **Initial remote providers:** Cloud SQL PostgreSQL/MySQL, AlloyDB PostgreSQL, Spanner GoogleSQL/PostgreSQL

## 1. Executive summary

This RFC proposes a dbt package that makes BigQuery federation a reusable, schema-aware source primitive rather than a collection of hand-written `EXTERNAL_QUERY` calls.

The core decision is:

> **Build one federation compiler in dbt macros. Make a runtime table-expression macro the primary interface. Implement code generation and `dbt run-operation` as alternate frontends over the same metadata, type-planning, and SQL-rendering engine. Do not implement a custom materialization.**

The compiler pipeline is:

```text
connection + remote relation + policy
               │
               ▼
       resolve provider/config
               │
               ▼
       discover source schema
               │
               ▼
      normalize source metadata
               │
               ▼
       plan type conversions
               │
               ▼
 choose cheapest correct SQL plan
               │
      ┌────────┼─────────┐
      ▼        ▼         ▼
 passthrough  option   projection
 SELECT *    widening   casts
      └────────┼─────────┘
               ▼
        BigQuery table expression
               │
               ▼
       ordinary dbt model SQL
               │
      ┌────────┼──────────┐
      ▼        ▼          ▼
     view     table   incremental
```

This boundary is intentional: federation determines **how a SELECT obtains and normalizes source rows**; dbt materializations determine **how that SELECT is persisted**.

The planner MUST preserve `SELECT * FROM T` when BigQuery can safely perform native mapping because BigQuery's documented `EXTERNAL_QUERY` pushdowns depend on that shape. Explicit source projections are generated only when correctness or user configuration requires them.

## 2. Problem statement

BigQuery federation is easy to start with:

```sql
select *
from external_query(
  'projects/example/locations/asia-northeast1/connections/app-pg',
  'select * from public.orders'
)
```

Production dbt usage introduces four problems.

### 2.1 Schema drift

Operational schemas change independently of dbt. Hard-coded projections go stale, but unqualified `SELECT *` can start failing when a newly added source column has a type unsupported by BigQuery federation.

Therefore schema discovery and type conversion are one problem, not two independent features.

### 2.2 Type fidelity

BigQuery automatically maps many MySQL/PostgreSQL/Spanner types, but Google documents important exceptions and semantic differences. PostgreSQL types such as `uuid`, `jsonb`, `money`, `inet`, and `interval` are unsupported in ordinary PostgreSQL federation and must be converted remotely. MySQL `GEOMETRY` and `BIT` are also documented as unsupported. PostgreSQL numeric precision can exceed BigQuery `NUMERIC` and even `BIGNUMERIC`.

A static `source_type -> BigQuery_type` map is insufficient. The package needs a planner that can choose native mapping, query-wide options, remote casts, post-processing, warnings, or failure.

### 2.3 Reproducibility versus automatic evolution

Live discovery gives the desired automatic catch-up behavior, but the same Git commit can compile differently after a source schema change. Some users want that; others require schema changes to be reviewed in Git.

Both live and pinned workflows must be first-class.

### 2.4 dbt v1/v2 evolution

The package should survive dbt's v1-to-v2/Fusion transition by relying on the dbt authoring layer—Jinja/macros, `run_query`, `execute`, vars, and normal model materializations—and avoiding Python adapter internals or custom persistence behavior.

## 3. Goals and non-goals

### Goals

The package MUST:

1. expose a natural table-expression macro for federated relations;
2. discover current source schemas through provider metadata;
3. use BigQuery native type mapping when safe;
4. automatically handle known unsupported types under a configurable policy;
5. support connection/type/table/column overrides;
6. follow source schema evolution in live mode;
7. offer a reproducible pinned/codegen mode;
8. compose with dbt `view`, `table`, `incremental`, and `ephemeral` semantics;
9. work across dbt Core v1.10+ and dbt v2/Fusion with explicit CI coverage;
10. separate provider-specific metadata/quoting from provider-independent planning;
11. provide inspection, validation, and schema-diff operations;
12. construct high-level remote SQL safely with provider-specific identifier/literal handling.

### Non-goals

The package is not:

- CDC or replication;
- an ingestion service;
- a new dbt adapter;
- a custom `federated` materialization;
- a manager for BigQuery connections, Cloud SQL, AlloyDB, Spanner, IAM, or credentials;
- a remote DDL/DML framework;
- initially, a persistent metadata cache service;
- initially, a manager for Spanner external datasets.

Infrastructure SHOULD be provisioned separately, preferably as infrastructure as code.

## 4. Repository baseline

The repository currently inherits `yu-iskw/dbt-package-template`. At RFC time:

- `dbt_project.yml` still uses `dbt_package_template`;
- README/test guidance still targets Postgres and DuckDB;
- the Core test matrix currently covers 1.10/1.11 rather than the intended BigQuery/v1/v2 matrix.

This RFC is documentation-only. The first implementation PR MUST convert the template to `dbt_bigquery_federation` and align tests/documentation before feature work.

The intended project constraint is:

```yaml
name: dbt_bigquery_federation
require-dbt-version: ">=1.10.0,<3.0.0"
```

## 5. Alternatives and decision

| Approach | Completeness | v1/v2 safety | Schema drift | Composability | Efficiency | Maintainability | Weighted result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Runtime macro only | 88 | 94 | 95 | 98 | 72 | 86 | 90 |
| Codegen only | 78 | 96 | 58 | 98 | 92 | 92 | 83 |
| `run-operation` managed views | 86 | 88 | 90 | 94 | 78 | 76 | 87 |
| Custom materialization | 87 | 62 | 92 | 58 | 76 | 52 | 74 |
| **Layered hybrid** | **96** | **92** | **96** | **99** | **88** | **84** | **94** |

Weights: completeness 25%, v1/v2 compatibility 20%, drift handling 20%, composability 15%, efficiency 10%, maintainability 10%.

### Decision

Choose the layered hybrid:

```text
                         shared compiler
                    ┌─────────┴─────────┐
                    │ metadata + types  │
                    │ + SQL planning    │
                    └─────────┬─────────┘
          ┌───────────────────┼────────────────────┐
          ▼                   ▼                    ▼
  runtime relation()     run-operation          codegen
  primary interface     inspect/validate     pinned workflow
```

A custom materialization is rejected because materializations are persistence strategies. Reimplementing federation as a materialization would couple the package to view/table/incremental lifecycle behavior, hooks, grants, schema-change handling, incremental strategies, and dbt internals unnecessarily.

## 6. Adversarial evaluation

### Central claim

A runtime macro plus shared compiler best satisfies automatic schema catch-up without taking ownership of dbt persistence.

### Strongest case for

- directly meets the automatic-evolution requirement;
- remains normal model SQL, so standard dbt materializations continue to work;
- one compiler can support runtime, codegen, and operations;
- provider/type logic stays testable and centralized.

### Strongest case against

**Nondeterminism:** live source metadata means the same Git revision can compile differently over time.

**Remote compilation dependency:** dbt documents that `run_query()` executes during connected compilation, including `dbt compile` and, by default, `dbt docs generate`.

**Pushdown loss:** BigQuery documents that `EXTERNAL_QUERY` pushdown is constrained to suitable `SELECT * FROM T` forms. Always emitting explicit casts/projections would sacrifice an important optimizer path.

### Resolution

The architecture remains recommended only with three safeguards:

1. live **and** pinned metadata modes;
2. explicit inspection/diagnostics around compile-time introspection;
3. a planner that preserves passthrough SQL unless conversion is necessary.

## 7. Public API

### 7.1 `federated_relation`

Primary table-expression API:

```sql
select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

Conceptual signature:

```text
federated_relation(
  connection,
  table,
  schema=None,
  columns=None,
  metadata_mode=None,
  type_policy=None,
  overrides=None,
  options=None
) -> SQL table expression
```

It MUST resolve config, discover metadata when appropriate, plan types, choose an execution plan, and render a BigQuery table expression.

### 7.2 `external_query`

Low-level escape hatch:

```sql
select *
from {{ dbt_bigquery_federation.external_query(
    connection='application_pg',
    sql='select id, created_at from public.orders'
) }}
```

This path is intentionally less managed and should be documented as trusted raw remote SQL.

### 7.3 Metadata and operations

Initial operational interfaces:

```text
get_remote_columns()
federation_inspect
federation_validate
federation_schema_diff
generate_federated_model
generate_federated_models
```

`federation_inspect` should explain every conversion, for example:

```text
COLUMN      SOURCE TYPE       TARGET       ACTION          LOSSINESS
id          bigint            INT64        passthrough     exact
user_uuid   uuid              STRING       remote_cast     representation
amount      numeric(50,20)    BIGNUMERIC   query_option    exact
payload     jsonb             STRING       remote_cast     representation
```

`federation_validate` SHOULD validate generated source expressions with source-side zero-row queries such as `WHERE 1=0`, rather than assume outer BigQuery `LIMIT` pushdown.

## 8. Configuration

Recommended shape:

```yaml
vars:
  dbt_bigquery_federation:
    connections:
      application_pg:
        connection_id: >-
          projects/analytics-prod/locations/asia-northeast1/connections/application-pg
        provider: cloud_sql_postgres
        defaults:
          schema: public
        metadata:
          mode: live
        types:
          policy: safe
          decimal: adaptive
          known_unsupported: string
          unknown: error
```

The package SHOULD require or strongly prefer fully qualified connection IDs:

```text
projects/PROJECT_ID/locations/LOCATION/connections/CONNECTION_ID
```

Google warns that non-fully-qualified connection IDs in shared views can resolve against the wrong project.

Override precedence:

```text
provider defaults
   ↓
package defaults
   ↓
connection
   ↓
source type
   ↓
table
   ↓
column
   ↓
macro invocation
```

Example:

```yaml
type_overrides:
  uuid:
    strategy: remote_cast
    remote_type: text
    target_type: STRING

tables:
  public.events:
    columns:
      payload:
        strategy: remote_cast
        remote_type: text
        target_type: STRING
```

## 9. Metadata modes

### `live` — default

Discover current metadata during connected compilation. Additions/removals/type changes are replanned automatically.

Pros: best schema catch-up. Cons: requires connectivity and weakens deterministic compilation.

### `pinned`

Use generated/declared metadata. No live source access is needed for planning.

Pros: reviewable and reproducible. Cons: must be regenerated when sources change.

### `cached` — deferred

A shared metadata cache is not part of v0.1. TTL, invalidation, concurrency, ownership, and staleness deserve a later RFC after benchmarks show a real need.

## 10. dbt parse and compile behavior

The package MUST never perform database access when `execute` is false.

During parse-only evaluation, `federated_relation` must emit a syntactically valid passthrough expression using static identifiers only.

During connected compilation in live mode, metadata discovery may use `run_query()`.

This distinction must be tested on:

```text
Core 1.10
Core 1.11
Core 1.12
Core 1.12 --use-v2-parser (where supported)
v2/Fusion BigQuery
```

Because dbt v2 performs stricter and earlier validation, provider routing should use parse-resolvable macros. The initial implementation SHOULD use an explicit provider router rather than dynamic calls to potentially nonexistent macro names.

## 11. Normalized schema model

Every provider MUST translate native `information_schema` rows into one stable internal model before type planning.

Conceptual representation:

```yaml
name: amount
ordinal_position: 5
nullable: true
source:
  provider: cloud_sql_postgres
  data_type: numeric
  raw_data_type: numeric(50,20)
  precision: 50
  scale: 20
  provider_metadata: {}
plan:
  classification: query_option
  action: query_option
  target_type: BIGNUMERIC
  lossiness: exact
  warnings: []
```

Provider code owns:

```text
information_schema -> normalized columns
```

Core compiler code owns:

```text
normalized columns -> conversion plan -> SQL plan
```

## 12. Provider abstraction

Initial provider operations:

```text
metadata_query(provider, relation)
quote_identifier(provider, identifier)
quote_literal(provider, value, logical_type)
normalize_type(provider, metadata_row)
render_remote_cast(provider, column, plan)
render_remote_relation(provider, relation)
```

Providers:

- `cloud_sql_postgres`
- `cloud_sql_mysql`
- `alloydb_postgres`
- `spanner_google_sql`
- `spanner_postgresql`

Cloud SQL PostgreSQL and AlloyDB can share a PostgreSQL family, but Spanner PostgreSQL remains distinct where type semantics differ.

Remote-provider routing is not the same as dbt `adapter.dispatch`: the dbt target adapter is BigQuery while the varying dimension is the remote database.

## 13. Type planner

Each column should be classified as one of:

```text
native_exact
native_risky
query_option
requires_remote_cast
requires_bigquery_postprocess
known_unsupported
unknown
user_overridden
```

and assigned lossiness:

```text
exact
representation_change
potentially_lossy
lossy
unknown
```

### Policies

**`native`**: prefer BigQuery's mappings/options and maximize passthrough.

**`safe` (default)**: automatically handle known unsupported/risky types conservatively. Known unsupported PostgreSQL values such as `uuid`/`jsonb` can be source-cast to text; unknown extension types fail rather than being silently guessed.

**`strict`**: compilation fails for unknown or potentially lossy conversions until explicitly acknowledged by an override.

### Decimal planning

BigQuery supports query-wide `default_type_for_decimal_columns` values `numeric`, `bignumeric`, `float64`, and `string` for MySQL `DECIMAL` and PostgreSQL `numeric`.

The planner SHOULD use that option before source projections:

```text
all decimals fit NUMERIC?
  ├─ yes -> SELECT * fast path
  └─ no
      ↓
all fit BIGNUMERIC and policy allows?
  ├─ yes -> SELECT * + bignumeric option
  └─ no -> projection / STRING / explicit failure
```

PostgreSQL unbounded/high-precision numeric must not be assumed to fit BigQuery. Under `safe`, STRING is the conservative exact textual fallback when representability cannot be proven; under `strict`, require an explicit choice.

### JSON

Cloud SQL/AlloyDB PostgreSQL `jsonb` is unsupported directly. Initial `safe` behavior should preserve it as serialized STRING. Automatic conversion to BigQuery JSON should be opt-in because it changes semantics and can introduce parsing/wide-number behavior.

## 14. Execution plans

The compiler SHOULD choose one of these plans.

### A. Passthrough fast path

```sql
external_query(connection, 'select * from public.orders')
```

Use whenever every requested column can be mapped correctly without source expressions.

### B. Passthrough plus query-wide option

```sql
external_query(
  connection,
  'select * from public.orders',
  '{"default_type_for_decimal_columns":"bignumeric"}'
)
```

Prefer this over per-column decimal casts when one query-wide option is valid.

### C. Projected remote normalization

```sql
external_query(
  connection,
  '''
  select
    id,
    cast(user_uuid as text) as user_uuid,
    amount,
    cast(payload as text) as payload,
    created_at
  from public.orders
  '''
)
```

Use only when necessary. The planner must record that automatic outer-query pushdown can no longer be assumed.

### D. Two-stage normalization

Remote normalization plus an outer BigQuery expression. This should be rare and opt-in in early releases.

## 15. Schema evolution and standard materializations

Live mode automatically replans:

- added columns;
- removed columns;
- precision/scale changes;
- type changes;
- newly unsupported columns.

This catches up the **federation SELECT**, not the history of persisted dbt tables. Standard dbt behavior continues to govern materialized schemas.

Example incremental model:

```sql
{{
  config(
    materialized='incremental',
    unique_key='id',
    on_schema_change='append_new_columns'
  )
}}

select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}

{% if is_incremental() %}
where updated_at > (
  select coalesce(max(updated_at), timestamp('1970-01-01'))
  from {{ this }}
)
{% endif %}
```

Documentation SHOULD recommend `append_new_columns` as a conservative starting point, but MUST NOT set it implicitly. `sync_all_columns` can be destructive/expensive and remains a user decision.

When the plan is native `SELECT *`, BigQuery may push supported outer filters into Cloud SQL/AlloyDB/Spanner. When normalization requires source expressions, pushdown cannot be assumed. Structured remote predicates may be a later API; v0.1 can use the low-level `external_query` escape hatch for performance-critical custom remote filters.

## 16. Why not ordinary dbt sources?

A Cloud SQL/AlloyDB relation referenced only through `EXTERNAL_QUERY` is not an ordinary BigQuery relation. Modeling it as a normal `source()` can create misleading relation lookup, catalog, freshness, grant, and quoting semantics.

Recommended boundary:

```text
remote table
    ↓ federated_relation()
base/staging dbt model
    ↓ ref()
normal dbt DAG
```

Spanner external datasets are different: they expose BigQuery-visible external relations and can be modeled as normal sources without this compiler.

## 17. Spanner

BigQuery supports Spanner through external datasets and through `EXTERNAL_QUERY`.

External datasets are attractive and support useful pushdowns, but currently have constraints relevant here: no `INFORMATION_SCHEMA` views on the BigQuery external dataset, only default-schema tables, inaccessible unsupported columns, no metadata cache, and Data Boost usage.

Therefore v0.x should use the shared `EXTERNAL_QUERY` compiler when the package needs metadata/type normalization. Existing Spanner external datasets should remain normal BigQuery relations. An automatic backend selector can be proposed later.

## 18. Operational and security requirements

### Locations

For Cloud SQL and AlloyDB, a BigQuery single region can query compatible sources in the same region; multi-region rules are defined by Google. Query processing location must match the BigQuery connection location.

The package SHOULD parse the connection location from canonical IDs and compare it with target location when available, failing for obvious incompatibilities and warning when validation is incomplete.

### Quotas and load

Google documents:

- up to 1 TB/project/day for cross-region federated querying;
- at most 10 unique connections in one federated query;
- no separate external-source workload quota configured by BigQuery;
- `maximum bytes billed` is not supported for federated queries.

Documentation SHOULD recommend source workload isolation: Cloud SQL read replicas, suitable AlloyDB read endpoints/read pools, and Spanner Data Boost where appropriate.

### Credentials

Package vars contain BigQuery connection resource IDs, not database passwords. The dbt identity needs appropriate BigQuery connection-use permissions and underlying source read permissions.

Connections SHOULD use least-privilege/read-only database identities.

### SQL injection boundary

High-level APIs MUST distinguish identifiers, typed literals, and trusted raw SQL. Provider-specific quoting is mandatory. Future remote filters should be structured rather than accepting arbitrary `WHERE` fragments by default.

The raw `external_query` macro is an explicit advanced escape hatch.

### Compiled artifacts

Compiled SQL can reveal remote schema/table names and user-provided literals. Documentation should warn that dbt `target/`, logs, and CI artifacts may contain rendered remote SQL.

## 19. Performance principles

1. Preserve `SELECT * FROM T` whenever correct.
2. Prefer `EXTERNAL_QUERY` query-wide options over per-column casts when they satisfy policy.
3. Scope metadata queries narrowly to one relation and only required metadata fields.
4. Do not promise cross-node in-memory metadata caching until validated across dbt threads and v1/v2 engines.
5. Avoid validation queries that accidentally scan full source tables.
6. Benchmark source load and bytes transferred, not only BigQuery wall-clock time.

A benchmark suite should compare:

```text
native SELECT * + outer filter
projected normalization + outer filter
explicitly filtered remote SQL
```

and inspect BigQuery query plans where practical.

## 20. Codegen and pinned workflow

Codegen uses the same compiler and normalized schema representation.

A strict-governance workflow is:

```text
source schema changes
      ↓
federation_schema_diff
      ↓
generate_federated_model
      ↓
Git diff / review
      ↓
merge pinned metadata/model
```

A pure dbt package SHOULD print generated SQL/YAML through `run-operation`; arbitrary filesystem writing is not required.

A `sync_federated_views` operation is deliberately excluded from v0.1 because it creates warehouse state and orchestration ordering. It can be reconsidered if users need shared normalized views outside dbt.

## 21. dbt v1/v2 compatibility

As of 2026-08-14, dbt documentation describes v2 as the current era delivered through Fusion, and gives `require-dbt-version: ">=1.10.0,<3.0.0"` as an example of a version constraint containing v2. BigQuery in the current v2/Fusion adapter matrix is marked Preview.

Recommended CI matrix:

```text
required:
  Core 1.10 + dbt-bigquery
  Core 1.11 + dbt-bigquery
  Core 1.12 + dbt-bigquery

preview lane:
  dbt v2/Fusion + BigQuery
```

The range expresses intent, while CI establishes actual support.

Implementation MUST avoid:

- Python adapter internals;
- parse-time database access;
- nonexistent/dynamically unresolved macros;
- custom materialization internals;
- v1-only deprecated Jinja behavior.

Core 1.12's v2 parser compatibility mode should be included where useful.

## 22. Testing strategy

### Layer 1: static/parse

Test Jinja/YAML, package namespace, parse-safe behavior, Core 1.10/1.11/1.12, and v2/Fusion.

### Layer 2: planner/rendering fixtures

Feed normalized metadata fixtures into the planner and assert plans/SQL for:

- PostgreSQL scalar types;
- `uuid`, `jsonb`, `money`, `inet`, `interval`;
- bounded/unbounded numerics;
- MySQL signed/unsigned integers and DECIMAL boundaries;
- MySQL `TIME`, `BIT`, `GEOMETRY`;
- Spanner GoogleSQL/PostgreSQL types;
- unknown extension types;
- quoting/reserved identifiers;
- override precedence.

### Layer 3: source-dialect tests

Dockerized PostgreSQL/MySQL can validate information-schema queries and cast syntax locally. These are not full federation tests.

### Layer 4: Google Cloud E2E

Real E2E needs BigQuery connections and real Cloud SQL/AlloyDB/Spanner sources. Terraform SHOULD manage test infrastructure. Prefer pre-provisioned/shared infrastructure plus isolated per-run schemas/databases rather than creating expensive services on every PR.

Schema-drift tests MUST exercise:

```text
initial schema
 -> add supported column
 -> add unsupported column
 -> precision/type change
 -> drop column
```

and verify live replanning.

The materialization matrix should cover view, table, incremental, and embedding/ephemeral behavior without implementing custom materializations.

## 23. Diagnostics

Debug output should expose:

- provider and connection alias;
- relation;
- metadata mode/type policy;
- selected plan class;
- query-wide options;
- converted columns;
- lossiness warnings;
- whether the passthrough fast path survived.

Errors should identify provider, table, column, raw source type, policy, and the override path needed to resolve the issue.

## 24. Target repository structure

```text
macros/
├── public/
│   ├── federated_relation.sql
│   ├── external_query.sql
│   └── get_remote_columns.sql
├── config/
├── metadata/
├── providers/
│   ├── router.sql
│   ├── postgres.sql
│   ├── mysql.sql
│   ├── spanner_google_sql.sql
│   └── spanner_postgresql.sql
├── types/
├── rendering/
├── operations/
└── codegen/

integration_tests/
└── terraform/   # or equivalent GCP fixture IaC

docs/rfcs/
└── 0001-bigquery-federation-architecture.md
```

The implementation should consolidate files where splitting creates indirection without value.

## 25. Implementation sequence

### Phase 0 — template conversion

Rename the package, replace Postgres/DuckDB target assumptions with BigQuery, update docs/agent guidance, and establish the v1/v2 BigQuery matrix.

### Phase 1 — federation foundation

Implement connection resolution, `external_query`, quoting, metadata discovery/normalization, and `federation_inspect`. Start with Cloud SQL PostgreSQL + AlloyDB.

### Phase 2 — planner + primary UX

Implement `native`/`safe`/`strict`, PostgreSQL unsupported types, decimal options, execution-plan selection, `federated_relation`, and view/table/incremental E2E tests.

### Phase 3 — MySQL

Add MySQL metadata, quoting, decimal/range edge cases, and Cloud SQL MySQL E2E.

### Phase 4 — Spanner

Add GoogleSQL/PostgreSQL provider logic, Spanner options, Data Boost guidance, and E2E coverage. Do not manage external datasets yet.

### Phase 5 — reproducibility tooling

Add pinned mode, model generation, and schema diff.

### Phase 6 — performance hardening

Benchmark large projects and source load. Only then decide whether shared metadata caching needs a new RFC.

## 26. Acceptance criteria

A production-capable release requires:

- live discovery for declared providers;
- documented handling or deliberate failure for known unsupported types;
- per-column overrides;
- precision-aware decimal planning;
- observable fast-path/projected-path selection;
- correct provider quoting;
- supported Core v1 CI lanes;
- a passing v2/Fusion BigQuery compatibility lane for supported behavior;
- no warehouse access during parse-only execution;
- normal dbt view/table/incremental interoperability;
- canonical connection handling and operational guidance;
- real federation E2E coverage for at least Cloud SQL PostgreSQL;
- no database credentials in package configuration.

## 27. Major risks

| Risk | Mitigation |
| --- | --- |
| Live source changes alter compiled SQL | Pinned mode, schema diff, strict policy |
| New unsupported column breaks raw federation | Live metadata + known-type normalization |
| Normalization disables pushdown | Passthrough/query-option fast paths and inspect output |
| Metadata calls make compile slow | Narrow queries; benchmark before cache |
| v2 parses differently | Parse-safe router and dedicated Fusion lane |
| Type conversion loses semantics | Lossiness model, strict policy, STRING fallback |
| Federation overloads source DB | Read replicas/read pools/Data Boost, concurrency guidance |
| Cross-region topology fails or burns quota | Canonical connection IDs and location checks/warnings |
| Raw remote SQL is unsafe | Structured high-level API; raw SQL as explicit escape hatch |

## 28. Open questions

1. Should safe mode map MySQL `TIME` to STRING by default because its range is wider than BigQuery TIME, or retain native mapping with a warning?
2. Should pinned metadata live in macro arguments, package vars, or generated properties YAML?
3. How much BigQuery post-processing (for example STRING -> JSON) belongs in the first release?
4. Is user-defined provider extension needed, or are package releases sufficient initially?
5. Should live introspection run during all connected compile/doc commands or support an explicit command policy?
6. Can metadata safely be memoized across nodes/threads in both engines?
7. When does a Spanner external-dataset backend provide enough value to warrant package-level support?

## 29. Final recommendation

Implement `dbt_bigquery_federation` as a **federation compiler**, not merely an `EXTERNAL_QUERY` wrapper and not a materialization.

The primary runtime experience should remain as small as:

```sql
select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

while the internal engine handles discovery, normalization, type policy, overrides, and plan selection.

The key implementation rule is:

> **Do not generate explicit per-column remote SQL merely because metadata is available. Generate it only when correctness or an explicit user request requires it.**

That rule preserves BigQuery federation optimization when possible while still allowing automatic schema and type normalization when necessary.

## 30. References

Platform facts were rechecked against official documentation on 2026-08-14.

### dbt

- v2 upgrade/package compatibility: <https://docs.getdbt.com/docs/dbt-versions/core-upgrade/upgrading-to-v2>
- v2 adapter guidance: <https://docs.getdbt.com/docs/contribute-core-adapters-v2>
- `run_query`: <https://docs.getdbt.com/reference/dbt-jinja-functions/run_query>
- materializations: <https://docs.getdbt.com/docs/build/materializations>
- incremental models: <https://docs.getdbt.com/docs/build/incremental-models>

### Google Cloud

- federation overview, regions, quotas, limitations, pushdown: <https://docs.cloud.google.com/bigquery/docs/federated-queries-intro>
- `EXTERNAL_QUERY`, options, type mappings: <https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/federated_query_functions>
- BigQuery data types: <https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types>
- Cloud SQL federation: <https://docs.cloud.google.com/bigquery/docs/cloud-sql-federated-queries>
- AlloyDB federation: <https://docs.cloud.google.com/bigquery/docs/alloydb-federated-queries>
- Spanner federation: <https://docs.cloud.google.com/bigquery/docs/spanner-federated-queries>
- Spanner external datasets: <https://docs.cloud.google.com/bigquery/docs/spanner-external-datasets>
- quotas: <https://docs.cloud.google.com/bigquery/quotas>
