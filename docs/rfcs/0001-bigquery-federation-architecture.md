# RFC-0001: Automation-First BigQuery Federation for dbt

- **Status:** Accepted (artifact-first revision)
- **Date:** 2026-08-14
- **Revised:** 2026-08-26
- **Package namespace:** `dbt_bigquery_federation`
- **Target warehouse:** BigQuery
- **Product objective:** make BigQuery federated queries instant to adopt and semi-automatic to operate from dbt
- **dbt compatibility objective:** dbt Core v1 and v2-compatible authoring APIs; exact supported versions are established by CI, not only by the install range
- **Initial provider sequence:** Cloud SQL PostgreSQL, AlloyDB PostgreSQL, Cloud SQL MySQL, Spanner GoogleSQL/PostgreSQL

## 1. Executive summary

`dbt_bigquery_federation` should make an operational table reachable from dbt with approximately one macro call **after** a generated pin exists:

```sql
select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

The package automatically performs the work that users otherwise repeat by hand:

1. resolve the BigQuery connection and remote provider;
2. inspect the remote relation schema in **run-operation** when discovery is requested;
3. normalize provider-specific metadata into one internal column model;
4. determine which source types BigQuery can federate natively;
5. choose query-wide `EXTERNAL_QUERY` options when appropriate;
6. generate remote casts for types that BigQuery cannot consume directly;
7. apply user overrides where automatic conversion is not appropriate;
8. render a BigQuery `EXTERNAL_QUERY(...)` table expression that composes with ordinary dbt models and materializations;
9. print generated pins so users can commit Git-reviewed IR under `vars` (or root `vars.yml` on dbt 1.12+);
10. validate pinned metadata against the live source in CI or an explicit operation.

The central decision of this RFC (2026-08-26 revision) is:

> **The package is automation-first and artifact-first. Live metadata discovery is a first-class capability of operations (`federation_inspect`, `federation_generate_pin`, `federation_schema_diff`, `federation_validate`). `federated_relation` always plans from a committed pin and never calls `run_query`. All modes reuse one provider/metadata/type-planning/rendering core.**

This supersedes the earlier hybrid that allowed `metadata_mode=live|auto` inside models. That path conflicted with dbt's compile/`docs generate` behavior: `execute` is `False` only during parse, while `run_query` still runs whenever compilation has a warehouse connection.

The package MUST NOT introduce a custom materialization. Federation determines how rows are obtained from an external database; dbt's existing `view`, `table`, `incremental`, and `ephemeral` behavior remains responsible for persistence.

The architecture is:

```text
                         user intent
              connection + schema + table
                              │
              ┌───────────────┴────────────────┐
              ▼                                ▼
     run-operation (live)              federated_relation
     inspect / generate /              (pin only; no I/O)
     diff / validate                           │
              │                                │
              ▼                                │
     normalized column IR ◄────────────────────┘
              │
              ▼
      type-policy planner
              │
              ▼
       SQL plan selection
              │
              ▼
    BigQuery EXTERNAL_QUERY
              │
              ▼
    ordinary dbt model SQL
```

A second important decision is that **schema stability and pushdown optimization are separate choices**. A remote `SELECT * FROM T` can preserve BigQuery's federation pushdown opportunities, but it does not isolate users from newly added remote columns. A stable/pinned projection does isolate the result schema, but may give up that optimization. The package must model and document this trade-off explicitly rather than claiming that one plan provides both guarantees. Model-path pins use stable projection so the pin is a real runtime boundary.

---

## 2. Product intent

### 2.1 User problem

BigQuery already supports federation through `EXTERNAL_QUERY`, but production dbt users still need to know and maintain several details:

- BigQuery connection resource identifiers;
- source SQL dialect and quoting;
- remote `information_schema` conventions;
- BigQuery's provider-specific type mappings;
- unsupported source types such as PostgreSQL `uuid` or `jsonb`;
- decimal precision/range behavior;
- location and connection constraints;
- schema changes in operational systems;
- whether generated remote SQL preserves federation pushdown opportunities.

A package that merely wraps:

```sql
EXTERNAL_QUERY(connection_id, remote_sql)
```

provides limited value. The package should instead make federation a **dbt-native source-access capability**.

### 2.2 Target experience

A new user should be able to:

1. configure an existing BigQuery connection;
2. run `federation_inspect` / `federation_generate_pin` against a remote table;
3. commit the printed pin under `vars.dbt_bigquery_federation.tables` (or root `vars.yml` on dbt 1.12+);
4. name that remote table in a dbt model via `federated_relation` without further metadata I/O;
5. later re-run generate/diff/validate when the source schema changes.

The happy path should require configuration comparable to:

```yaml
vars:
  dbt_bigquery_federation:
    connections:
      application_pg:
        connection_id: "{{ env_var('BQ_APP_PG_CONNECTION_ID') }}"
        provider: cloud_sql_postgres
    tables:
      application_pg.public.orders:
        columns:
          - name: id
            data_type: bigint
```

and model SQL comparable to:

```sql
select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

Column YAML is generated, not hand-authored. Remote `schema` is always explicit at the call site (use `schema=''` for Spanner GoogleSQL's default schema).

### 2.3 Product principles

1. **Automation first.** Discover information that already exists instead of asking users to duplicate it by hand.
2. **Artifact-first models.** `federated_relation` plans only from committed IR; live discovery is an operation.
3. **Progressive governance.** Generate pins, then validate drift in CI.
4. **Explain every conversion.** Automatic behavior must remain inspectable.
5. **Fail conservatively on unknown semantics.** Unknown source types are not silently guessed.
6. **Prefer native BigQuery behavior.** Do not generate source casts when BigQuery can safely handle a type itself.
7. **Do not own persistence.** Use existing dbt materializations.
8. **Provider logic is explicit.** Remote-provider dispatch is separate from dbt adapter dispatch.
9. **Performance trade-offs are observable.** Users should know when normalization prevents the `SELECT *` fast path.
10. **No hidden infrastructure.** The package does not create connection resources or source databases.
11. **One planning engine, multiple frontends.** Runtime macros, inspection, validation, and generated pins share the same normalized schema/type engine.
12. **Honor dbt compile semantics.** Never rely on `{% if execute %}` to "skip" warehouse I/O during `compile` / `docs generate`.

---

## 3. Goals and non-goals

### 3.1 Goals

The package MUST eventually provide:

1. a table-expression macro for federated relations that plans from pins only;
2. live schema discovery through BigQuery federation metadata queries in operations;
3. automatic type planning and provider-aware source conversions;
4. user-configurable conversion policies and per-column overrides;
5. deterministic model compilation with no warehouse metadata I/O;
6. generated pins so users do not hand-author large schemas;
7. a `validate` operation that compares pins with live metadata;
8. source inspection and schema-diff operations;
9. provider support for Cloud SQL PostgreSQL, AlloyDB PostgreSQL, Cloud SQL MySQL, and Spanner;
10. compatibility with normal dbt `view`, `table`, `incremental`, and `ephemeral` usage where the generated SQL is valid;
11. real BigQuery compile coverage and real federation E2E coverage for supported providers;
12. diagnostic output that explains type actions, lossiness, source projection, and pushdown eligibility;
13. strong identifier/literal handling at every high-level API boundary.

### 3.2 Non-goals

The package is not:

- CDC or replication;
- an ingestion framework;
- a dbt adapter;
- a custom federation materialization;
- an IAM or credential manager;
- a creator of Cloud SQL/AlloyDB/Spanner databases;
- a replacement for Terraform or other infrastructure-as-code;
- a generic remote DDL/DML execution framework;
- a general-purpose cross-database SQL transpiler;
- a real-time catalog/indexing service.

A persistent shared metadata cache is also out of the first implementation unless benchmarking shows that metadata access materially harms large projects.

---

## 4. Why live discovery inside `federated_relation` is insufficient

An earlier revision made live discovery the default model path (with parse stubs when `execute=false`). That improves first-run UX, but it conflicts with dbt's compile contract and with reproducible builds.

### 4.1 `execute` does not protect compile/docs

`execute` is `False` only during parse. `run_query` still runs during `dbt compile` and `dbt docs generate` when a warehouse connection is available. Model-path discovery therefore hits OLTP during ordinary compile workflows.

### 4.2 Parse stubs diverge from executed SQL

A `SELECT *` stub during parse and a planned projection during connected compile are different SQL texts for the same Git revision.

### 4.3 Hand-authored pins without generation are still insufficient

Requiring users to manually author large column lists duplicates remote schemas. Generation via `federation_generate_pin` is mandatory product UX; hand-authoring is not the happy path.

### 4.4 Pin inspection is not source inspection

An operation called `federation_inspect` should primarily tell users what exists remotely and what the package will do with it. Reading back YAML the user already wrote is useful for debugging, but it is not the primary inspection experience.

### 4.5 Pin + `SELECT *` does not actually pin runtime schema

If a pin declares three columns but generated source SQL is `select * from public.orders`, a new fourth remote column is still returned at execution time. Therefore this RFC separates:

- **metadata source**: live (operations) vs pinned (models);
- **remote projection policy**: passthrough vs stable projection.

Model-path pins use stable projection.

---

## 5. Alternatives and decision

### 5.1 Alternatives

| Approach                           | Instant UX | Automatic evolution | Governance | Determinism | Complexity | Recommendation      |
| ---------------------------------- | ---------: | ------------------: | ---------: | ----------: | ---------: | ------------------- |
| Always live discovery in models    |  Very high |           Very high |        Low |         Low |     Medium | Rejected for models |
| Mandatory hand-authored pins only  |        Low |                 Low |       High |        High |        Low | Rejected            |
| Codegen committed SQL models       |     Medium |              Medium |       High |        High |     Medium | Deferred            |
| Shared metadata registry           |       High |                High |       High |        High |  Very high | Defer               |
| **Artifact-first pins + live ops** |   **High** |       **Very high** |   **High** |    **High** | **Medium** | **Selected**        |

### 5.2 Decision

Adopt an artifact-first architecture:

```text
models:    pin IR → plan → EXTERNAL_QUERY   (no run_query)
operations: live discovery ↔ IR             (run_query expected)
```

`federation_generate_pin` is the recommended onboarding path. `metadata_mode=live|auto` on `federated_relation` MUST raise a compiler error.

### 5.3 Adversarial evaluation

#### Central claim

An artifact-first package provides the best overall product because it keeps Hub-native distribution while making parse, compile, docs, and run emit the same SQL.

#### Strongest case for

- The remote database already owns authoritative schema metadata (operations discover it).
- BigQuery explicitly permits `EXTERNAL_QUERY` to query `information_schema` metadata.
- Type planning is substantially more useful when driven by real source metadata (via generated pins).
- Generated pins eliminate most manual governance work.
- `validate` allows CI to detect drift without requiring every normal dbt command to introspect the source.
- dbt docs state that `run_query` runs during `compile` and `docs generate`; model-path discovery is therefore unsafe.

#### Strongest case against

- First query requires a generate-and-commit step.
- Pins can go stale until validation runs.

#### Resolution

Make the generate step the product's explicit onboarding, with actionable missing-pin errors that name `federation_generate_pin`. Do not reintroduce parse stubs that emit different SQL than execute.

---

## 6. Public API

### 6.1 `federated_relation`

Primary API:

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
  type_policy=None,
  overrides=None,
  metadata_mode=None
) -> SQL table expression
```

`schema` is required at runtime (Jinja default `None` fails with a compiler error). Pass `schema=''` for Spanner GoogleSQL's default schema. Connection config must not include `defaults`.

`metadata_mode` is a compatibility argument only: omitted or `pinned` is accepted; `live` and `auto` MUST raise a compiler error directing users to operations.

Responsibilities:

1. resolve the connection;
2. load normalized metadata from the pin (`vars.dbt_bigquery_federation.tables`);
3. classify source columns;
4. select query-wide options and source casts;
5. render the remote query safely;
6. render `EXTERNAL_QUERY`.

`federated_relation` MUST NOT call `run_query`.

### 6.2 `external_query`

Low-level escape hatch:

```sql
select *
from {{ dbt_bigquery_federation.external_query(
    connection='application_pg',
    sql='select id, created_at from public.orders'
) }}
```

This bypasses:

- schema discovery;
- pin validation;
- type planning;
- identifier safety beyond the connection itself;
- schema-stability guarantees.

It MUST be documented as trusted raw remote SQL.

### 6.3 `get_remote_columns`

Provider-neutral metadata API:

```jinja
{% set columns = dbt_bigquery_federation.get_remote_columns(
    connection='application_pg',
    schema='public',
    table='orders'
) %}
```

This is primarily an internal/advanced API but is useful for operations and custom tooling.

It MUST return normalized columns rather than provider-native rows.

### 6.4 `federation_inspect`

```bash
dbt run-operation federation_inspect \
  --args '{connection: application_pg, schema: public, table: orders}'
```

Default behavior plans from the configured pin (`live=false`). Pass `live=true` to discover and plan from the current source schema.

The signature keeps `type_policy` and `overrides` after `live` so inspect can mirror a `federated_relation` invocation and positional `true` still means `live`:

```text
federation_inspect(
  connection,
  schema,
  table,
  live=false,
  type_policy=None,
  overrides=None
)
```

Do not reorder those kwargs.

Example:

```text
Connection: application_pg
Provider: cloud_sql_postgres
Relation: public.orders
Metadata: live
Projection: passthrough
Automatic pushdown: eligible

COLUMN          SOURCE TYPE         TARGET       ACTION          LOSSINESS
id              bigint              INT64        native          exact
user_uuid       uuid                STRING       remote_cast     representation_change
amount          numeric(50,20)      BIGNUMERIC   query_option    exact
metadata        jsonb               STRING       remote_cast     representation_change
created_at      timestamptz         TIMESTAMP    native          exact

Remote SQL:
SELECT
  "id",
  CAST("user_uuid" AS text) AS "user_uuid",
  "amount",
  CAST("metadata" AS text) AS "metadata",
  "created_at"
FROM "public"."orders"
```

### 6.5 `federation_generate_pin`

```bash
dbt run-operation federation_generate_pin \
  --args '{connection: application_pg, schema: public, table: orders}'
```

The operation SHOULD print deterministic YAML suitable for copy/commit rather than requiring the dbt package to write arbitrary files.

Output shape:

```yaml
tables:
  application_pg.public.orders:
    columns:
      - name: id
        data_type: bigint
        nullable: false
      - name: amount
        data_type: numeric
        precision: 30
        scale: 8
        nullable: true
```

A future helper/CLI outside pure dbt Jinja may optionally write files, but printing canonical YAML is sufficient for the package API.

### 6.6 `federation_schema_diff`

```bash
dbt run-operation federation_schema_diff \
  --args '{connection: application_pg, schema: public, table: orders}'
```

Compares pin versus live metadata.

Example:

```diff
 public.orders

+ customer_segment text
~ amount numeric(30,2) -> numeric(50,20)
- legacy_status character varying
```

The machine-readable result SHOULD classify:

```text
added
removed
type_changed
nullability_changed
precision_changed
scale_changed
ordering_changed
```

### 6.7 `federation_validate`

Validation operation intended for CI:

```bash
dbt run-operation federation_validate
```

or scoped:

```bash
dbt run-operation federation_validate \
  --args '{connection: application_pg, schema: public, table: orders}'
```

Policies should support:

```text
error_on:
  - removed_column
  - incompatible_type_change
  - unsupported_added_column

warn_on:
  - supported_added_column
  - column_order_change
```

### 6.8 Optional generated model helpers

After the runtime/discovery APIs are stable, codegen MAY be offered:

```text
generate_federated_model
generate_federated_models
generate_federated_source_properties
```

These are frontends over the same discovery/planner core, not separate implementations.

---

## 7. Metadata modes

Model path and operations path are separate.

### 7.1 Model path — pinned IR only

`federated_relation` always uses declared metadata under `vars.dbt_bigquery_federation.tables`.

Benefits:

- reproducible planning across parse, compile, docs, and run;
- no metadata lookup;
- suitable for restricted CI/production networks;
- Git review of schema/type changes.

A missing pin MUST fail with an actionable message naming `federation_generate_pin`.

Passing `metadata_mode='live'` or `'auto'` MUST fail. Do not emit a parse stub that differs from the planned SQL.

### 7.2 Operations — live discovery

`federation_inspect` (with `live=true`), `federation_generate_pin`, `federation_schema_diff`, and `federation_validate` MAY call `run_query` against the metadata connection. That I/O is expected for those commands.

### 7.3 Validate

Use the pin as the runtime plan but also query live metadata and compare it (operation only).

Validation MUST NOT silently rewrite the runtime plan.

### 7.4 Historical note: `auto` / model `live`

Earlier revisions made `auto` the recommended default inside models (prefer pin when present, else live during connected compilation). That design is withdrawn because:

- `execute` is `False` only during parse ([dbt docs](https://docs.getdbt.com/reference/dbt-jinja-functions/execute));
- `run_query` still runs during `dbt compile` and `dbt docs generate` ([dbt docs](https://docs.getdbt.com/reference/dbt-jinja-functions/run_query));
- parse stubs produced different SQL than connected compilation for the same Git revision.

### 7.5 Future `cached`

A persistent/shared metadata cache is deferred.

If added, it requires a separate design for:

- cache ownership;
- TTL;
- invalidation;
- concurrency;
- environment isolation;
- secrets/IAM;
- stale-schema behavior.

Do not build it before measurements justify it.

---

## 8. Command and parse behavior

The correct rule is:

> **`federated_relation` never performs database I/O. Live discovery is reserved for explicit operations.**

### 8.1 Parse / compile / docs / run

When dbt evaluates `federated_relation`, the macro loads the pin and plans. Behavior MUST be identical whether `execute` is `False` (parse) or `True` (compile/run/docs).

There is no parse stub and no `SELECT *` fallback.

### 8.2 `dbt run` / `dbt build` / `dbt compile` / `dbt docs generate`

Model compilation does not query remote `information_schema`. Source connectivity is not required to compile federated models once pins exist.

### 8.3 `run-operation`

Operations whose purpose is discovery/inspection/validation SHOULD perform live metadata access explicitly.

```text
ordinary dbt build → pin-only planning
explicit operations → discovery is expected
```

---

## 9. Configuration model

Recommended configuration:

```yaml
vars:
  dbt_bigquery_federation:
    connections:
      application_pg:
        connection_id: "{{ env_var('BQ_APP_PG_CONNECTION_ID') }}"
        provider: cloud_sql_postgres
        types:
          policy: safe

      application_mysql:
        connection_id: "{{ env_var('BQ_APP_MYSQL_CONNECTION_ID') }}"
        provider: cloud_sql_mysql

    tables:
      application_pg.public.orders:
        columns:
          - name: id
            data_type: bigint
          - name: amount
            data_type: numeric
            precision: 30
            scale: 8

    type_overrides:
      money:
        strategy: remote_cast
        remote_type: text
        target_type: STRING
```

On dbt Core 1.12+, the same `vars` mapping MAY live in a root `vars.yml` file. The package continues to read `var('dbt_bigquery_federation')` and does not bump `require-dbt-version` solely for that feature.

### 9.1 Fully qualified connection IDs

The package SHOULD require canonical fully qualified BigQuery connection resource IDs:

```text
projects/PROJECT_ID/locations/LOCATION/connections/CONNECTION_ID
```

This avoids ambiguous project resolution in reusable views/models and allows the package to parse the configured connection location for diagnostics.

Different dbt targets MAY use different `env_var` names or target-scoped vars for `connection_id`. Do not treat a single production connection resource path as the only configuration.

### 9.2 Override precedence

Use one deterministic precedence chain:

```text
provider built-in behavior
        ↓
package defaults
        ↓
connection defaults
        ↓
source-type override
        ↓
table configuration
        ↓
column/pin configuration
        ↓
macro invocation override
```

Every inspect plan SHOULD report when a user override changed a built-in choice.

---

## 10. Normalized schema model

Every provider MUST translate metadata into one canonical model before type planning.

Conceptual column representation:

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
  action: query_option
  target_type: BIGNUMERIC
  remote_type: null
  lossiness: exact
  warnings: []
```

Required normalized fields should include, where provider metadata supplies them:

```text
name
ordinal_position
data_type
raw_data_type
nullable
precision
scale
length
array/struct metadata where relevant
provider-specific metadata bag
```

Pins SHOULD use a serializable subset of the same normalized model so live and pinned planning cannot diverge by design.

Provider code owns:

```text
information_schema rows -> normalized schema
```

Planner code owns:

```text
normalized schema -> type actions -> query plan -> SQL
```

---

## 11. Remote metadata discovery

BigQuery `EXTERNAL_QUERY` supports querying external database metadata, including `information_schema`. The discovery layer should use that mechanism rather than require direct credentials from dbt to the source database.

### 11.1 PostgreSQL family

Conceptual query:

```sql
select *
from external_query(
  '<connection>',
  '''
  select
      column_name,
      ordinal_position,
      data_type,
      udt_name,
      is_nullable,
      character_maximum_length,
      numeric_precision,
      numeric_scale,
      datetime_precision
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'orders'
  order by ordinal_position
  '''
)
```

Use both `data_type` and provider-specific metadata such as `udt_name` where needed to distinguish extension/domain/native types accurately.

### 11.2 MySQL

Implement a provider-specific metadata query and normalize into the same model.

Important metadata includes:

- `DATA_TYPE`;
- `COLUMN_TYPE` for signed/unsigned distinctions;
- precision/scale;
- datetime precision;
- character length;
- nullability.

### 11.3 Spanner GoogleSQL

Spanner has different information-schema fields, including type strings such as `spanner_type`. Normalize these into the canonical model.

### 11.4 Spanner PostgreSQL dialect

Treat this as a distinct provider even when some metadata resembles PostgreSQL. Do not assume Cloud SQL PostgreSQL type semantics are identical.

### 11.5 Metadata query safety

High-level metadata queries MUST:

- quote identifiers/literals with provider-specific routines;
- scope to the requested relation;
- select only needed metadata columns;
- never scan source data rows;
- avoid remote DDL/DML;
- produce deterministic ordering by ordinal position.

---

## 12. Provider architecture

Initial provider interface:

```text
metadata_query(provider, relation)
normalize_metadata(provider, rows)
quote_identifier(provider, identifier)
quote_literal(provider, value)
normalize_type_name(provider, column)
type_entry(provider, column)
render_remote_relation(provider, relation)
render_remote_cast(provider, column, action)
render_provider_options(provider, plan)
```

Remote-provider routing MUST remain distinct from dbt `adapter.dispatch`.

The dbt target is BigQuery. The remote provider may be PostgreSQL, MySQL, or Spanner. They are separate axes.

Recommended provider layout:

```text
macros/federation/providers/
  router.sql
  cloud_sql_postgres.sql
  alloydb_postgres.sql
  cloud_sql_mysql.sql
  spanner_google.sql
  spanner_postgres.sql
```

Cloud SQL PostgreSQL and AlloyDB can share PostgreSQL-family helpers internally, but provider names should remain explicit because capabilities and operational recommendations can differ.

---

## 13. Type-planning model

The type planner is a core product feature.

Each column should be classified into an action such as:

```text
native
query_option
remote_cast
bigquery_postprocess
fail
```

and lossiness such as:

```text
exact
representation_change
potentially_lossy
lossy
unknown
```

### 13.1 Policies

#### `native`

Prefer BigQuery's built-in mappings and query-wide options. Fail only when federation itself would fail and no explicitly configured fallback exists.

This mode prioritizes minimal source SQL and pushdown opportunities.

#### `safe` — recommended default

Automatically handle known unsupported types conservatively. Preserve information where practical, commonly through textual representation, and fail unknown types rather than guess.

“Safe” means **safe for predictable federation behavior**, not “all semantic types remain identical.” Inspect output must surface representation changes.

#### `strict`

Fail on unsupported, unknown, potentially lossy, or representation-changing conversions until the user explicitly acknowledges an override.

This is useful for governed environments.

### 13.2 PostgreSQL examples

Typical behavior:

```text
smallint / integer / bigint       -> INT64
real / double precision           -> FLOAT64
boolean                           -> BOOL
text / varchar / char             -> STRING
bytea                             -> BYTES
date                              -> DATE
timestamp without time zone       -> DATETIME
timestamp with time zone          -> TIMESTAMP
numeric                           -> NUMERIC/BIGNUMERIC/other plan
bit / bit varying / varbit        -> BYTES (native)
json                              -> STRING (native; do not map to BigQuery JSON)
uuid                              -> remote cast to text under safe
jsonb                             -> remote cast to text under safe
money                             -> remote cast or explicit override
inet/cidr/macaddr                 -> remote cast to text under safe
interval                          -> remote cast to text under safe
pg_lsn / tsquery / tsvector / txid_snapshot -> remote cast to text under safe
arrays                            -> unknown (not in Google's Cloud SQL EXTERNAL_QUERY map)
unknown extension/domain type     -> fail unless explicitly configured
```

Do not assume all PostgreSQL domains/extensions normalize safely from `information_schema.data_type`; provider metadata such as `udt_name` may be required.

### 13.3 MySQL examples

Provider support must explicitly test:

- signed and unsigned integer ranges;
- `DECIMAL` boundaries;
- `TIME` range/semantics;
- `BIT`;
- `GEOMETRY`;
- temporal precision;
- binary/text types.

Do not copy the PostgreSQL table and rename types.

### 13.4 Spanner

Spanner type planning must account for dialect-specific mapping, nested/struct types where federation permits them, timestamp precision behavior, and provider options such as query execution priority where applicable.

---

## 14. Decimal planning

BigQuery `EXTERNAL_QUERY` supports a query-wide `default_type_for_decimal_columns` option for MySQL `DECIMAL` and PostgreSQL `numeric`, including `numeric`, `bignumeric`, `float64`, and `string`.

The planner SHOULD prefer query-wide native options before per-column casts when they preserve requested semantics.

Conceptual algorithm:

```text
collect decimal columns
      │
      ▼
can default mapping represent all safely?
      ├─ yes -> no option, native SQL
      └─ no
          │
          ▼
can one wider query option represent all safely?
      ├─ yes -> SELECT * + query-wide option
      └─ no
          │
          ▼
policy allows per-column fallback?
      ├─ yes -> project/cast only offenders
      └─ no  -> fail with exact columns/reasons
```

The implementation MUST not reduce BigQuery BIGNUMERIC to an incorrect simplistic integer precision rule. BigQuery documents BIGNUMERIC as having approximately 76.76 digits of precision and scale up to 38; representability checks must either implement the actual documented range or deliberately define a conservative supported subset and label it as such.

Unknown/unbounded PostgreSQL numeric precision should not be assumed to fit.

The current pin-planner decimal fold MUST keep these Google option rules:

- omitted `EXTERNAL_QUERY` options JSON means Google's default `default_type_for_decimal_columns=NUMERIC`;
- never emit `"numeric"`;
- emit `"bignumeric"` when **any** remaining native decimal needs `BIGNUMERIC`, including a mix of NUMERIC-fit and BIGNUMERIC-fit siblings after unbounded offenders are remote-cast;
- widening NUMERIC-range values to `BIGNUMERIC` stays exact;
- remote-cast only unbounded/overflow offenders under `safe`; do not stringify a well-typed `numeric(12,2)` because a sibling unbounded `numeric` exists.

---

## 15. Projection modes and schema stability

Metadata mode and projection mode are independent.

Recommended projection modes:

```text
auto
passthrough
stable
```

### 15.1 `passthrough`

Remote SQL:

```sql
select * from "public"."orders"
```

Advantages:

- preserves the query shape BigQuery can use for federation SQL pushdowns;
- automatically returns newly added supported source columns.

Disadvantages:

- the runtime schema is whatever exists remotely, not the pin;
- a new unsupported column can break a previously working query;
- the result schema can change without Git changes.

### 15.2 `stable`

Remote SQL explicitly lists the planned columns:

```sql
select
  "id",
  "amount",
  "created_at"
from "public"."orders"
```

Advantages:

- the chosen metadata schema is an actual runtime boundary;
- new source columns do not appear until the plan changes;
- pinned mode becomes truly pinned.

Disadvantages:

- BigQuery's documented `SELECT * FROM T` pushdown path should not be assumed;
- source/network cost can increase depending on workload.

### 15.3 `auto`

Suggested policy:

- in live mode, prefer passthrough if all discovered columns are natively safe and the user has not requested a stable schema;
- in pinned mode, prefer stable projection because users chose reproducibility/governance;
- if any conversion requires remote expressions, use projection regardless;
- inspect output MUST state the selected projection mode and whether automatic pushdown remains eligible.

This fixes the earlier design contradiction between pins and remote `SELECT *`.

---

## 16. Query plan classes

The planner should distinguish at least the following.

### 16.1 Native passthrough

```sql
EXTERNAL_QUERY(
  '<connection>',
  'select * from "public"."orders"'
)
```

Omitting the options JSON selects Google's `NUMERIC` default. Never emit `"numeric"`.

When that `SELECT * FROM T` shape survives, BigQuery may prune columns and push filters. Filter literals are limited to the Google-listed types; `NUMERIC`, `BIGNUMERIC`, `TIME`, and `BYTES` are not among them.

### 16.2 Passthrough with query-wide options

```sql
EXTERNAL_QUERY(
  '<connection>',
  'select * from "public"."orders"',
  '{"default_type_for_decimal_columns":"bignumeric"}'
)
```

Use when **any** remaining native decimal needs `BIGNUMERIC`, including a mix of NUMERIC-fit and BIGNUMERIC-fit siblings after offender casts.

### 16.3 Stable projection

```sql
EXTERNAL_QUERY(
  '<connection>',
  'select "id", "amount", "created_at" from "public"."orders"'
)
```

### 16.4 Normalizing projection

```sql
EXTERNAL_QUERY(
  '<connection>',
  '''
  select
    "id",
    cast("user_uuid" as text) as "user_uuid",
    "amount",
    cast("payload" as text) as "payload"
  from "public"."orders"
  '''
)
```

### 16.5 Two-stage normalization

Some conversions may require remote normalization followed by a BigQuery expression. This should be introduced only for concrete use cases and generally be opt-in initially.

For example, automatic STRING-to-JSON conversion changes validation/error semantics and should not be silently introduced merely because a source column is `jsonb`.

---

## 17. Schema evolution

The package should make schema drift behavior explicit by mode.

### 17.1 Live + passthrough

```text
remote change
   ↓
next connected planning/execution
   ↓
new schema automatically observed
```

Most automatic, least reproducible.

### 17.2 Live + stable

The package discovers the current schema and generates an explicit projection each time planning occurs.

Automatically tracks source changes but protects the SQL from additional columns between discovery and the next planning cycle only to the extent the source projection remains valid.

### 17.3 Pinned + stable

Most reproducible.

Remote additions are ignored. Remote removals or incompatible changes to pinned columns fail at execution unless preflight validation is used.

### 17.4 Pinned + passthrough

Allowed only as an explicit performance-oriented choice because the pin does not define the runtime output schema.

Documentation MUST call this out clearly.

### 17.5 Validate

Recommended CI workflow:

```text
source schema changes
      │
      ▼
federation_validate
      │
      ├─ compatible addition -> warn/allow according to policy
      ├─ unsupported addition -> fail/warn according to projection mode
      ├─ removal -> fail
      └─ incompatible type change -> fail
```

---

## 18. Interaction with dbt materializations

Federation should remain a table-expression concern.

### 18.1 View

```sql
{{ config(materialized='view') }}

select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

### 18.2 Table

```sql
{{ config(materialized='table') }}

select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

### 18.3 Incremental

```sql
{{
  config(
    materialized='incremental',
    unique_key='id',
    on_schema_change='fail'
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

The package MUST NOT set `on_schema_change` implicitly.

When the plan is native `SELECT * FROM T`, BigQuery may prune columns and push supported outer filters into Cloud SQL. Filter literals are the Google-listed types, not `NUMERIC` / `BIGNUMERIC` / `TIME` / `BYTES`. When normalization requires source expressions, pushdown cannot be assumed.

Documentation should explain that an outer incremental predicate can be pushed down only when BigQuery's federation optimizer can apply SQL pushdowns. If normalization changes the source query away from the supported fast-path shape, users with high-volume sources may need an explicit remote predicate or the low-level `external_query` API.

A later high-level structured remote-filter API may be considered, but arbitrary raw `where` strings should not be the default high-level interface.

---

## 19. dbt `source()` integration

A remote Cloud SQL/AlloyDB table reached only through `EXTERNAL_QUERY` is not an ordinary BigQuery relation. Pretending it is a normal dbt source can create confusing database/schema/catalog/freshness behavior.

The initial recommendation remains:

```text
remote relation
     ↓ federated_relation()
staging/base dbt model
     ↓ ref()
normal dbt DAG
```

However, dbt source YAML is a natural declaration surface. A later RFC SHOULD explore metadata such as:

```yaml
sources:
  - name: application_pg
    meta:
      federation:
        connection: application_pg
        schema: public
    tables:
      - name: orders
```

and a helper such as:

```sql
{{ dbt_bigquery_federation.federated_source('application_pg', 'orders') }}
```

This must not rely on a fake BigQuery relation lookup.

Spanner external datasets are different because their tables are BigQuery-visible external relations and may be modeled as ordinary dbt sources.

---

## 20. Spanner strategy

BigQuery supports Spanner through both `EXTERNAL_QUERY` and external datasets.

### 20.1 External dataset

Prefer ordinary BigQuery relation semantics when a user already has a Spanner external dataset and does not require package-level source normalization.

The package should not unnecessarily wrap those tables in `EXTERNAL_QUERY`.

### 20.2 `EXTERNAL_QUERY`

Useful when users explicitly use a Spanner connection and need provider-level metadata/type planning or query options.

Both GoogleSQL and PostgreSQL dialects should be modeled separately.

### 20.3 No automatic backend switching initially

Do not silently switch a user from `EXTERNAL_QUERY` to an external dataset. Those approaches differ in infrastructure, IAM, Data Boost behavior, metadata visibility, and supported features.

---

## 21. Operational and security requirements

### 21.1 Credentials

Package configuration contains BigQuery connection resource IDs, not source database passwords.

The package does not manage the connection's underlying credentials.

### 21.2 Least privilege

Documentation SHOULD recommend a read-only source identity for federation and source-side workload isolation where appropriate.

For Cloud SQL/AlloyDB production systems, users should consider read replicas/read endpoints where federation load could affect transactional workloads.

### 21.3 Locations

BigQuery federation is location-sensitive. The connection location and query processing location must be compatible with the source and referenced BigQuery datasets.

The package SHOULD parse location from fully qualified connection IDs and include it in diagnostics.

It MAY validate obvious incompatibilities when target location is available reliably, but it must not invent correctness when context is incomplete.

The current pin-planner does not fail compilation on a location mismatch (the package test target is Postgres and has no BigQuery location). Operators must align locations in GCP.

### 21.4 Quotas and cost

Documentation should surface federation limitations relevant to production planning, including connection limits, cross-region data transfer/quotas where applicable, and the fact that source systems incur their own workload/cost.

Google documents:

- at most 10 unique connections in one federated query;
- a cross-region federated-query bytes quota;
- `maximum bytes billed` is not supported for federated queries.

Isolate Cloud SQL from federated load with a read replica. Compile-time planning does not enforce these quotas.

### 21.5 SQL injection boundary

High-level APIs MUST never concatenate untrusted raw fragments.

Distinguish:

```text
identifier
literal
structured option
trusted raw SQL
```

Provider-specific quoting is mandatory for identifiers and literals.

The current pin-planner **always** PostgreSQL-quotes identifiers (double quotes; internal quotes doubled). There is no unquoted-if-safe path.

Only `external_query` is the explicit raw-SQL escape hatch.

### 21.6 Compiled artifacts

Compiled SQL can expose:

- connection resource IDs;
- source schema/table names;
- source SQL;
- user-supplied literal values.

Document that `target/`, dbt logs, and CI artifacts should be handled accordingly.

---

## 22. Performance principles

1. Preserve remote `SELECT * FROM T` when correctness and requested schema semantics allow it.
2. Prefer a query-wide `bignumeric` option over per-column casts when remaining native decimals need it, including a mix of NUMERIC-fit and BIGNUMERIC-fit siblings after offender casts. Never emit `"numeric"`.
3. Keep metadata discovery narrow and relation-scoped.
4. Never scan source rows merely to discover a schema.
5. Report when a plan loses automatic pushdown eligibility.
6. Benchmark source CPU/IO and transferred rows/bytes, not only BigQuery elapsed time.
7. Do not add a shared cache before observing real metadata-query bottlenecks.

Benchmark scenarios SHOULD include:

```text
native SELECT * + outer projection/filter
stable explicit projection
normalizing projection with remote casts
explicit remote filter
```

For each, capture:

- BigQuery job/query plan;
- pushed-down operations where visible;
- source query load;
- bytes/rows returned;
- wall-clock latency.

---

## 23. Testing strategy

The package cannot claim BigQuery federation support based only on a PostgreSQL Jinja runner.

### 23.1 Layer 1: pure planner tests

No GCP required.

Test:

- config precedence;
- pin parsing;
- normalized metadata fixtures;
- provider type maps;
- quoting;
- decimal boundaries, including mixed remaining native decimals that take `decimal_option=bignumeric` and never emit `"numeric"`;
- conversion policies;
- projection selection;
- generated remote SQL strings;
- schema diffs.

### 23.2 Layer 2: dbt Core compile matrix with dbt-bigquery

Required before release claims.

Use the actual `dbt-bigquery` adapter to verify:

- package namespace/dispatch;
- parsing;
- model compilation;
- BigQuery-specific macro contexts;
- v1 and v2 compatibility for supported versions.

This lane need not execute external queries if credentials/infrastructure are unavailable, but it must use the correct target adapter.

### 23.3 Layer 3: source-dialect containers

Docker Compose runs PostgreSQL (`integration_tests/docker-compose.dialect.yml`, host port **5433**) and the Spanner emulator to validate:

- information-schema metadata queries generated by the package;
- identifier quoting;
- remote cast / projection SQL that becomes the `EXTERNAL_QUERY` remote body;
- normalization of live metadata rows into the column IR.

Entry point: `make run-dialect-extract-tests` (pytest under `integration_tests/tests/dialect/`). SQL is always produced via `dbt run-operation` export macros; pytest executes it on the dialect engines. This is not federation E2E (no BigQuery Connections / `EXTERNAL_QUERY` transport).

### 23.4 Layer 4: real Google Cloud federation E2E

Required for production-ready provider support.

Terraform SHOULD provision or reference test infrastructure:

```text
BigQuery dataset
BigQuery connection
Cloud SQL PostgreSQL
Cloud SQL MySQL
AlloyDB (when economical/appropriate)
Spanner
service accounts / IAM
```

Prefer reusable/pre-provisioned expensive databases with isolated test schemas where per-PR provisioning is impractical.

E2E scenarios MUST include:

```text
metadata discovery
native relation
unsupported type conversion
decimal boundaries
identifier edge cases
source column addition
unsupported source column addition
source column removal
type change
pinned validation
projection-mode behavior
view/table/incremental dbt models
```

### 23.5 Compatibility matrix

Do not equate `require-dbt-version` with verified support.

Document separately:

```text
installable range
required/tested Core versions
preview/experimental v2 or Fusion lanes
unsupported versions
```

As dbt v2 evolves, prefer public Jinja/package authoring APIs and avoid Python adapter internals so the package can share behavior across engines.

---

## 24. Diagnostics and observability

Every plan should expose a structured diagnostic object internally.

Recommended fields:

```yaml
provider: cloud_sql_postgres
connection: application_pg
connection_id: projects/.../connections/application-pg
relation: public.orders
metadata_source: pinned
projection_mode: stable
type_policy: safe
pushdown_eligible: false
query_options:
  default_type_for_decimal_columns: bignumeric
warnings: []
columns:
  - name: id
    source_type: bigint
    target_type: INT64
    action: native
    lossiness: exact
```

Human-readable `federation_inspect` output is rendered from the same object.

Do not report pushdown as a per-column guarantee. Pushdown eligibility is a query-plan property.

---

## 25. Repository architecture

Recommended structure:

```text
macros/
  federated_relation.sql
  external_query.sql

  federation/
    config.sql
    metadata.sql
    normalize.sql
    pins.sql
    diff.sql
    plan.sql
    render.sql
    inspect.sql
    validate.sql
    codegen.sql

    providers/
      router.sql
      postgres_family.sql
      cloud_sql_postgres.sql
      alloydb_postgres.sql
      cloud_sql_mysql.sql
      spanner_google.sql
      spanner_postgres.sql

  properties.yml

integration_tests/
  macros/tests/
  models/
  docker-compose.postgres.yml
  docker-compose.mysql.yml
  terraform/

docs/
  rfcs/
    0001-bigquery-federation-architecture.md
```

Avoid splitting macros so aggressively that ordinary changes require navigating dozens of one-function files. Provider-family helpers are appropriate where behavior is genuinely shared.

---

## 26. Implementation sequence

### Phase 0 — package identity and real BigQuery compile lane

- convert template identity fully to `dbt_bigquery_federation`;
- remove obsolete template examples;
- establish dbt-bigquery compile CI;
- retain inexpensive local macro test infrastructure as useful;
- document exact support matrix.

### Phase 1 — live PostgreSQL discovery foundation

Implement:

```text
connection resolution
EXTERNAL_QUERY renderer
PostgreSQL quoting
metadata query
normalized schema model
get_remote_columns
federation_inspect (live)
```

Target Cloud SQL PostgreSQL first.

Acceptance: a user can inspect a real remote table without hand-writing its schema.

### Phase 2 — type planner and primary runtime UX

Implement:

```text
native/safe/strict policies
known PostgreSQL mappings
unsupported-type handling
decimal planner
remote casts
projection modes
federated_relation
```

Acceptance: a user can query a typical PostgreSQL table from one macro call.

### Phase 3 — pins and governance

Implement:

```text
pinned mode (required for federated_relation)
federation_generate_pin
schema diff
federation_validate
stable projection default for pinned metadata
```

Acceptance: teams generate pins from live metadata and compile models from committed IR without redesigning models.

### Phase 4 — AlloyDB PostgreSQL

Reuse PostgreSQL family behavior but add independent integration/E2E coverage and provider-specific operational guidance.

### Phase 5 — Cloud SQL MySQL

Implement MySQL metadata normalization, type map, signed/unsigned behavior, decimal boundaries, temporal edge cases, and E2E.

### Phase 6 — Spanner

Implement GoogleSQL and PostgreSQL dialect providers for `EXTERNAL_QUERY` and document interaction with Spanner external datasets.

### Phase 7 — codegen/source integration

Evaluate:

```text
generate_federated_model
source.meta declarations
federated_source helper
bulk discovery/generation
```

Only add these after the core runtime and metadata APIs are stable.

### Phase 8 — performance hardening

Benchmark large schemas/projects and decide whether:

- metadata memoization;
- a persistent cache;
- structured remote incremental predicates;
- bulk metadata operations

need separate RFCs.

---

## 27. Migration from the existing pin-only implementation

Useful existing components should be preserved where possible:

```text
connection resolver
provider router
PostgreSQL type map
EXTERNAL_QUERY renderer
quoting routines
pin representation
type planner concepts
federated_relation public entrypoint
```

Required changes:

1. remove live/`auto` metadata modes from `federated_relation`;
2. keep live metadata acquisition as a provider capability for operations only;
3. make pins mandatory for model compilation;
4. make `federation_inspect` inspect the source when `live=true`;
5. keep generated pins and schema diff;
6. separate projection mode from metadata source;
7. ensure pinned/stable plans explicitly project pinned columns;
8. correct decimal/BIGNUMERIC boundary assumptions;
9. add dbt-bigquery and real federation test layers;
10. document that `run_query` during `compile`/`docs generate` is why models must not discover.

Preserve the current pin-planner's always-quoted identifiers, Google type-map additions (`bit` / `varbit`, `pg_lsn` / search types, native `json`, unknown arrays), and decimal-option fold (omit `"numeric"`; emit `"bignumeric"` for remaining native mix). Do not throw away working planner tests.

Reframe fixture pins as normalized-metadata fixtures and test the same planner with both discovered and pinned inputs.

---

## 28. Acceptance criteria

A production-capable first release for Cloud SQL PostgreSQL requires all of the following.

### User experience

- A new user can configure one connection, generate a pin, and query a table without hand-authoring columns.
- `federation_inspect` reports live source schema and conversion decisions when `live=true`.
- Known unsupported PostgreSQL types are handled according to policy.
- Unknown types produce actionable errors.
- `federated_relation` never calls `run_query`; missing pins name `federation_generate_pin`.

### Metadata and governance

- Model compilation is pin-only and documented.
- Pins can be generated from live metadata.
- Live-versus-pin schema differences can be reported.
- CI validation can fail on configured drift classes.

### Correctness

- Provider metadata query is tested against PostgreSQL.
- Type-map fixtures cover every supported provider type entry.
- Decimal boundary behavior is documented and tested.
- Pinned + stable mode produces an actual explicit schema projection.
- High-level SQL uses provider quoting rather than raw concatenation.

### dbt compatibility

- Required dbt Core versions pass a real dbt-bigquery compile lane.
- Parse-only execution never requires source metadata access.
- Standard `view`, `table`, and `incremental` examples compile and execute in E2E where applicable.

### Google Cloud E2E

- At least one real Cloud SQL PostgreSQL connection is exercised.
- Metadata discovery executes through BigQuery.
- Native and normalized federated queries both execute successfully.
- Schema-drift scenarios are covered.

### Operations

- Connection/location requirements are documented.
- Source workload recommendations are documented.
- Compiled artifact sensitivity is documented.
- No source database credentials are required in package vars.

---

## 29. Major risks and mitigations

| Risk                                                    | Impact                 | Mitigation                                                              |
| ------------------------------------------------------- | ---------------------- | ----------------------------------------------------------------------- |
| Live discovery changes compiled SQL without Git changes | Reproducibility        | pinned mode, generated pins, validate mode                              |
| Metadata access makes compile/build slower              | Developer experience   | narrow metadata queries, pins, benchmark before caching                 |
| Source schema adds unsupported column                   | Runtime failure        | live discovery + normalization, or stable projection in pinned mode     |
| Stable projection loses pushdown                        | Source/network cost    | explicit projection mode, inspect diagnostics, benchmarks               |
| Unknown extension type is guessed incorrectly           | Data correctness       | fail unknown types by default                                           |
| Type normalization loses semantics                      | Data correctness       | lossiness model, strict policy, explicit overrides                      |
| dbt v1/v2 parse behavior differs                        | Compatibility          | public APIs only, actual CI matrix, parse tests                         |
| Source DB is overloaded                                 | Production reliability | read replicas/read endpoints, query guidance, monitoring                |
| Location mismatch                                       | Runtime failure/cost   | canonical IDs, diagnostics, validation where context permits            |
| Raw SQL escape hatch is abused                          | Security/correctness   | explicit trusted API, high-level structured APIs by default             |
| Too many provider branches make Jinja unmaintainable    | Maintainability        | normalized schema contract, provider family helpers, focused interfaces |

---

## 30. Future RFC candidates

These should not block the core automation-first implementation:

1. persistent metadata cache / registry;
2. structured remote predicates for high-volume incremental models;
3. dbt `source.meta` integration;
4. external-provider plugin interface;
5. advanced BigQuery post-processing such as JSON normalization;
6. Spanner external-dataset helper/provisioning integration;
7. bulk database/schema discovery and automatic staging-model generation;
8. observability metrics for source query load;
9. metadata snapshots as first-class artifacts outside `vars`;
10. optional companion CLI for writing generated YAML/files.

---

## 31. Final recommendation

Build `dbt_bigquery_federation` as an **automation-first, artifact-first federation compiler and workflow**, not as a live-in-compile SQL generator.

The package should optimize the path from:

```text
“I already have a BigQuery connection to my operational database.”
```

to:

```text
“I can inspect it, generate a pin, and use that table in a dbt model safely.”
```

with one connection configuration, one generate step, and one macro call.

The default model experience should plan from committed IR. Live discovery remains available through operations so schema catch-up does not require redesigning models.

The most important architectural rules are:

> **Discover what can be discovered in operations; require a pin for model compilation.**

> **Use one normalized metadata/type planner for pinned, validation, and code-generation workflows.**

> **Keep metadata source separate from projection mode so schema stability and federation pushdown are explicit trade-offs.**

> **Do not implement a custom materialization; federation remains a source-access concern.**

> **Never call `run_query` from `federated_relation`.**

---

## 32. References

Platform assumptions should be rechecked as implementations land because dbt and Google Cloud federation features continue to evolve.

### dbt

- dbt Developer Hub: <https://docs.getdbt.com/>
- `run_query`: <https://docs.getdbt.com/reference/dbt-jinja-functions/run_query>
- `execute`: <https://docs.getdbt.com/reference/dbt-jinja-functions/execute>
- `dispatch`: <https://docs.getdbt.com/reference/dbt-jinja-functions/dispatch>
- materializations: <https://docs.getdbt.com/docs/build/materializations>
- incremental models: <https://docs.getdbt.com/docs/build/incremental-models>
- package/version documentation: <https://docs.getdbt.com/docs/build/packages>

### Google Cloud

- BigQuery federated queries overview: <https://docs.cloud.google.com/bigquery/docs/federated-queries-intro>
- `EXTERNAL_QUERY` and external type mappings/options: <https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/federated_query_functions>
- Cloud SQL federated queries: <https://docs.cloud.google.com/bigquery/docs/cloud-sql-federated-queries>
- AlloyDB federated queries: <https://docs.cloud.google.com/bigquery/docs/alloydb-federated-queries>
- Spanner federated queries: <https://docs.cloud.google.com/bigquery/docs/spanner-federated-queries>
- Spanner external datasets: <https://docs.cloud.google.com/bigquery/docs/spanner-external-datasets>
- BigQuery data types: <https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types>
- BigQuery query plan explanation for federated queries: <https://docs.cloud.google.com/bigquery/docs/query-plan-explanation>
- BigQuery connections: <https://docs.cloud.google.com/bigquery/docs/connections-api-intro>
