# RFC-0001: BigQuery Federation Compiler for dbt v1 and v2

- **Status:** Proposed (revised)
- **Date:** 2026-08-14
- **Revised:** 2026-08-14 (adversarial review: pinned-default, v0.1 scope cut)
- **Package namespace:** `dbt_bigquery_federation`
- **Target:** BigQuery
- **dbt compatibility objective (install range):** `>=1.10.0,<3.0.0`
- **Supported CI:** dbt Core 1.10 and 1.11 with a Postgres Jinja execution target
- **v0.1 remote provider:** Cloud SQL PostgreSQL (`cloud_sql_postgres`)

## 1. Executive summary

This RFC proposes a dbt package that makes BigQuery federation a reusable, schema-aware source primitive rather than a collection of hand-written `EXTERNAL_QUERY` calls.

The core decision is:

> **Build a pinned federation planner in dbt macros. Make a runtime table-expression macro the primary interface. Plan only from Git-reviewed vars. Do not discover remote schemas during compile. Do not implement a custom materialization.**

v0.1 compilation is a pure function of Git + vars. Automatic live catch-up is explicitly out of scope.

The planner pipeline is:

```text
connection + remote relation + pinned columns + policy
               │
               ▼
       resolve provider/config
               │
               ▼
       plan type conversions (decision table + decimal fold)
               │
               ▼
        choose SQL body × decimal option
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
```

This boundary is intentional: federation determines **how a SELECT obtains and normalizes source rows**; dbt materializations determine **how that SELECT is persisted**.

The planner MUST preserve `SELECT * FROM T` when BigQuery can safely perform native mapping because BigQuery's documented `EXTERNAL_QUERY` pushdowns depend on that shape. Explicit source projections are generated only when correctness or an explicit override requires them.

## 2. Problem statement

BigQuery federation is easy to start with:

```sql
select *
from external_query(
  'projects/example/locations/asia-northeast1/connections/app-pg',
  'select * from public.orders'
)
```

Production dbt usage introduces four problems. v0.1 addresses the first two with pinned metadata; the third is deferred.

### 2.1 Schema drift

Operational schemas change independently of dbt. Hard-coded projections go stale, but unqualified `SELECT *` can start failing when a newly added source column has a type unsupported by BigQuery federation.

v0.1 treats the pin list as the reviewed contract: adding an unsupported column does not break production until someone updates the pin and reviews the plan.

### 2.2 Type fidelity

BigQuery automatically maps many PostgreSQL types, but Google documents important exceptions. PostgreSQL types such as `uuid`, `jsonb`, `money`, `inet`, and `interval` are unsupported in ordinary PostgreSQL federation and must be converted remotely. PostgreSQL numeric precision can exceed BigQuery `NUMERIC` and even `BIGNUMERIC`.

A static `source_type -> BigQuery_type` map is insufficient when decimals mix bounded and unbounded precision. The package needs a **decision table plus a relation-level decimal fold**, not an open-ended compiler.

### 2.3 Reproducibility versus automatic evolution

Live discovery gives automatic catch-up, but the same Git commit can compile differently after a source schema change. dbt's contract is that the same Git SHA plus the same vars compiles the same SQL.

v0.1 chooses reproducibility. Live compile-time `run_query()` is rejected: `execute` is false only during parse, so "no I/O when `execute` is false" does not protect `dbt compile` or `dbt docs generate`.

### 2.4 dbt v1/v2 evolution

The package should survive dbt's v1-to-v2/Fusion transition by relying on the dbt authoring layer—Jinja/macros, vars, and normal model materializations—and avoiding Python adapter internals or custom persistence behavior. Fusion BigQuery is Preview; it is not a v0.1 support gate.

## 3. Goals and non-goals

### v0.1 MUST

1. expose `federated_relation` as a table-expression macro that renders `EXTERNAL_QUERY(...)`;
2. plan types from **pinned** normalized column metadata in package vars (available at parse; no warehouse I/O);
3. preserve remote `SELECT * FROM T` when every pinned column is natively safe, or a single query-wide decimal option makes them all safe;
4. under `safe`, remote-cast known-unsupported PostgreSQL types to `text` and fail on unknown types;
5. support connection / type / column overrides with one documented precedence ladder;
6. compose with stock `view`, `table`, and `incremental` (the user owns `on_schema_change`; examples use `fail`);
7. never call `run_query` from `federated_relation`;
8. always quote identifiers through the provider quoter (PostgreSQL: double quotes, internal quotes doubled);
9. keep public macros overridable via `adapter.dispatch(..., 'dbt_bigquery_federation')` → `default__*`;
10. cover Core 1.10 and 1.11 with planner/parse tests that do **not** require GCP.

### v0.1 MUST NOT

- live compile-time discovery;
- `columns=` on the primary macro;
- MySQL or Spanner providers;
- codegen file writers;
- schema-diff as a product;
- Terraform / GCP E2E as an acceptance gate;
- a persistent metadata cache;
- Plan D (BigQuery post-process, including automatic STRING → JSON);
- a `native` policy that emits failing `SELECT *`;
- Fusion as a required CI gate;
- implicit `on_schema_change`.

### Non-goals (package lifetime)

The package is not:

- CDC or replication;
- an ingestion service;
- a new dbt adapter;
- a custom `federated` materialization;
- a manager for BigQuery connections, Cloud SQL, AlloyDB, Spanner, IAM, or credentials;
- a remote DDL/DML framework.

Infrastructure SHOULD be provisioned separately, preferably as infrastructure as code.

## 4. Repository baseline

This repository started as `yu-iskw/dbt-package-template` (Postgres/DuckDB, `dbt_package_template`). Implementation of this RFC converts identity to `dbt_bigquery_federation` and **keeps Postgres as the Jinja macro-runner**, dropping DuckDB as a dbt target. Postgres is not the federation warehouse; it is the GCP-free test engine.

The intended project constraint is:

```yaml
name: dbt_bigquery_federation
require-dbt-version: ">=1.10.0,<3.0.0"
```

The upper bound is an **install** range so Fusion users can depend on the package. **Supported** behavior is whatever required CI proves: Core 1.10 and 1.11 planner/parse tests on Postgres.

## 5. Alternatives and decision

Alternatives considered:

- **Runtime macro with live compile-time `run_query`.** Meets automatic evolution; makes `compile` / `docs generate` federate against OLTP `information_schema`; parse SQL can diverge from compile SQL. Rejected for v0.1.
- **Pinned vars as the only planner input; inspect as `run-operation`.** Compile is a pure function of Git + vars. Discovery, if added later, is an explicit reviewable step. **Selected.**
- **`source()` as the pin/declaration surface in v0.1.** Better long-term DX, but a second product (graph identity, freshness, fake database/schema rules) on top of an unbuilt planner. Deferred.
- **Custom materialization.** Would couple the package to view/table/incremental lifecycle, hooks, grants, and dbt internals. Fusion-hostile. Rejected. Because the package then has **no runtime hook**, live-at-compile discovery is also rejected.

A numeric scoring table is not used. Completeness of "has every frontend" is not a reason to ship codegen, inspect-as-product-suite, and five providers in v0.1.

## 6. Adversarial evaluation (revised)

### Central claim

A runtime macro plus a **pinned** decision-table planner best satisfies type-safe `EXTERNAL_QUERY` generation without taking ownership of dbt persistence or compile-time warehouse I/O.

### Strongest case for

- remains normal model SQL, so standard dbt materializations continue to work;
- compilation is reviewable in Git;
- provider/type logic stays testable with fixtures and no GCP;
- one private renderer can serve `federated_relation` and the raw `external_query` hatch.

### Strongest case against, and the v0.1 resolution

**Nondeterminism:** live metadata means the same Git revision can compile differently over time. **Resolution:** pins only. Live is not a v0.1 mode.

**Remote compilation dependency:** `run_query()` runs during connected compilation, including `dbt compile` and default `dbt docs generate`. **Resolution:** `federated_relation` never calls `run_query`. Pins are vars, so the real plan is rendered at parse.

**Pushdown loss:** BigQuery documents that `EXTERNAL_QUERY` pushdown is constrained to `SELECT * FROM T`. **Resolution:** no `columns=` on the primary macro. Users prune on the BigQuery side. Projection is emitted only when a type conversion requires it, and inspect reports `pushdown=lost`.

**Jinja as a compiler:** an open-ended type solver in Jinja will not stay reviewable. **Resolution:** versioned type maps plus a small relation fold. No two-stage post-process in v0.1.

**Fusion Preview as a support claim:** BigQuery on Fusion is Preview. **Resolution:** non-blocking Fusion lane; do not advertise Fusion BigQuery as supported.

**Five providers and GCP E2E as v0.1:** cannot be verified in this repository. **Resolution:** Cloud SQL PostgreSQL only; GCP E2E is a later RFC.

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

Signature:

```text
federated_relation(
  connection,
  table,
  schema=None,
  type_policy=None,
  overrides=None
) -> SQL table expression
```

There is no `columns`, `metadata_mode`, or `options` argument.

It MUST resolve config, load the pin, plan types, and render a BigQuery table expression. A missing pin is `exceptions.raise_compiler_error`.

To return a subset of columns **without** disabling remote pushdown, project on the BigQuery side:

```sql
select id, amount
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

### 7.2 `external_query`

Low-level escape hatch:

```sql
select *
from {{ dbt_bigquery_federation.external_query(
    connection='application_pg',
    sql='select id, created_at from public.orders'
) }}
```

This path is trusted raw remote SQL. The dbt identity executes this string on the remote database. The compiler uses a **private** renderer; the public hatch never runs the planner.

### 7.3 `federation_inspect`

`run-operation` (and a callable macro) that prints the inspect table from **pins**:

```text
COLUMN      SOURCE TYPE       TARGET       ACTION          LOSSINESS              PUSHDOWN
id          bigint            INT64        passthrough     exact                  kept
user_uuid   uuid              STRING       remote_cast     representation_change  lost
```

The operation also reports provider, connection alias, relation, policy, body class, and query-wide decimal option.

Signature:

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

Optional `type_policy` and `overrides` follow `live` so inspect can mirror a `federated_relation` invocation. Positional `true` still means `live`.

An optional `live=true` argument is reserved. v0.1 MUST error if `live` is true: live metadata is not implemented.

Dropped from the v0.1 public surface: `get_remote_columns`, `federation_validate`, `federation_schema_diff`, `generate_federated_model`, `generate_federated_models`.

### 7.4 Parse contract

Pins are vars, so they are available when `execute` is false. `federated_relation` renders the **real plan** at parse. There is no dummy `SELECT *` stub. If the pin is missing, parse fails.

## 8. Configuration

One nested shape:

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

`connection_id` MUST match:

```text
^projects/[^/]+/locations/[^/]+/connections/[^/]+$
```

Different dbt targets MAY use different `env_var` names or target-scoped vars for `connection_id`. Do not treat a single production connection resource path as the only configuration.

v0.1 provider key: `cloud_sql_postgres` only.

Override precedence (implement exactly this):

```text
package defaults
   ↓
connection types.policy
   ↓
type_overrides (by source type)
   ↓
table/column pin fields (strategy / remote_type / target_type)
   ↓
macro invocation type_policy / overrides
```

Macro `overrides` is a mapping keyed by column name:

```yaml
user_uuid:
  strategy: remote_cast
  remote_type: text
  target_type: STRING
```

## 9. Metadata modes

### `pinned` — v0.1, the only mode

Use declared metadata in vars. No live source access is used for planning.

### `live` — deferred

Compile-time discovery is not part of v0.1. A later RFC may add an explicit opt-in that is documented as CI-unsafe. It MUST NOT be the default.

### `cached` — deferred

A shared metadata cache is not part of v0.1.

## 10. dbt parse and compile behavior

`federated_relation` MUST never call `run_query`, regardless of `execute`.

Because pins are vars, parse and compile emit the same SQL for the same Git + vars.

Provider routing MUST use parse-resolvable macros: an explicit `if/elif` router whose callees all exist in the package. Do not dynamically invoke potentially nonexistent macro names.

## 11. Normalized schema model

Pins are already the internal model. Each column:

```yaml
name: amount
data_type: numeric
raw_data_type: numeric(12,2)   # optional
precision: 12                  # optional; null/absent => unbounded
scale: 2                       # optional; null/absent => unbounded
nullable: true                 # optional
strategy: remote_cast          # optional pin-level override
remote_type: text              # optional
target_type: STRING            # optional
```

Provider code owns quoting, remote relation rendering, remote casts, and the type map.

Core planner code owns: pin lookup → column actions → decimal fold → query plan → SQL body.

## 12. Provider abstraction

v0.1 operations:

```text
quote_identifier(provider, identifier)
quote_literal(provider, value)
normalize_type_name(provider, data_type)
type_map(provider)
render_remote_cast(provider, column, plan)
render_remote_relation(provider, schema, table)
```

Remote-provider routing is not dbt `adapter.dispatch`: the dbt target adapter is BigQuery (or, in this repo's tests, Postgres as a Jinja engine) while the varying dimension is the remote database.

Public macros still use `adapter.dispatch(..., 'dbt_bigquery_federation')` so consumers can override via `search_order`. Internal remote dialect uses the explicit router.

AlloyDB PostgreSQL, Cloud SQL MySQL, and Spanner are later RFCs. Do not accept those provider keys in v0.1.

## 13. Type planner

This is a **decision table + relation fold**, not a general compiler.

Column actions: `passthrough` | `remote_cast` | `fail`.

Query plan:

```text
(body: passthrough | projection) × (decimal_option: none | bignumeric)
```

Omitted options JSON means Google's default `default_type_for_decimal_columns=NUMERIC`. Never emit `"numeric"`. Emit `"bignumeric"` when **any** remaining native decimal needs `BIGNUMERIC`.

These dimensions combine. A table with `jsonb` and mixed decimals may be **projection + no decimal option**. Stop treating exclusive A/B/C/D plans as the model.

Policies:

- **`safe` (default):** known unsupported types are remote-cast to `text`; unknown types fail.
- **`strict`:** known unsupported and unknown types fail until an override acknowledges them.

There is no `native` policy in v0.1.

Lossiness values: `exact` | `representation_change` | `unknown`.

### Decimal fold

BigQuery `NUMERIC` is precision 38 / scale 9 (29 integer digits). `BIGNUMERIC` is precision 76 / scale 38.

- All decimal columns have proven precision/scale that fit `NUMERIC` → passthrough body, omit options JSON (`decimal_option=none`). Google's omitted-options default is `NUMERIC`. Never emit `"numeric"`.
- Else all remaining native decimals fit `BIGNUMERIC` and at least one needs it → passthrough body when there are no remote casts, `decimal_option=bignumeric`.
- Else under `safe`: remote-cast **only** the offenders to `text`; leave fitting decimals native; body becomes projection; warn that pushdown is lost. Under `strict`: fail the offenders.
- After remote-casting unbounded offenders, remaining native decimals that mix NUMERIC-fit and BIGNUMERIC-fit take `decimal_option=bignumeric`. Widening NUMERIC-range values to `BIGNUMERIC` stays exact. The alternative (omit the option and remote-cast BIGNUMERIC-fit columns) would lose precision.
- Null/absent precision or scale ⇒ unbounded ⇒ offender.
- Never stringify a well-typed `numeric(12,2)` because a sibling unbounded `numeric` exists.

### Known-unsupported PostgreSQL (v0.1 map)

Remote-cast to `text` under `safe` (Google's unsupported list, plus common aliases): `uuid`, `jsonb`, `money`, `inet`, `cidr`, `macaddr`, `macaddr8`, `interval`, `time with time zone`, `timetz`, `pg_lsn`, `tsquery`, `tsvector`, `txid_snapshot`, and geometric types (`point`, `line`, `lseg`, `box`, `path`, `polygon`, `circle`).

Native mappings: `bit`, `bit varying`, and alias `varbit` map natively to BigQuery `BYTES`.

`json` maps natively to BigQuery `STRING` — keep passthrough. Do not map `json` to BigQuery `JSON`.

Arrays are `unknown` (not in Google's Cloud SQL `EXTERNAL_QUERY` map). Unknown types, including arrays and extension types, fail under both policies until an override acknowledges them.

## 14. Execution plans

### Passthrough

```sql
EXTERNAL_QUERY(
  'projects/.../connections/...',
  '''select * from "public"."orders"'''
)
```

Use when every pinned column can be mapped without a source expression and no query-wide option is required. Omitting the options JSON selects Google's `NUMERIC` default.

### Passthrough plus query-wide option

```sql
EXTERNAL_QUERY(
  'projects/.../connections/...',
  '''select * from "public"."orders"''',
  '{"default_type_for_decimal_columns":"bignumeric"}'
)
```

Use when **any** remaining native decimal needs `BIGNUMERIC`, including a mix of NUMERIC-fit and BIGNUMERIC-fit siblings after offender casts. Never emit `"numeric"`.

### Projected remote normalization

```sql
EXTERNAL_QUERY(
  'projects/.../connections/...',
  '''
  select
    "id",
    cast("user_uuid" as text) as "user_uuid",
    "amount",
    cast("payload" as text) as "payload",
    "created_at"
  from "public"."orders"
  '''
)
```

Use only when at least one column requires a remote expression. Inspect MUST report `pushdown=lost`.

Google's limitation, verbatim: SQL pushdowns are only applied to federated queries of the form `SELECT * FROM T`. Any explicit remote column list, including an uncasted list, disables that path. When that shape survives, BigQuery may prune columns and push filters. Filter literals are limited to the Google-listed types; `NUMERIC`, `BIGNUMERIC`, `TIME`, and `BYTES` are not among them.

Two-stage BigQuery post-process is out of v0.1.

## 15. Schema evolution and standard materializations

v0.1 does not automatically replan when the remote schema changes. Updating pins is a Git review.

Standard dbt behavior governs materialized schemas. Incremental examples MUST use `on_schema_change='fail'` unless the user explicitly chooses otherwise. The package MUST NOT set `on_schema_change` implicitly.

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

When the plan is native `SELECT * FROM T`, BigQuery may prune columns and push supported outer filters into Cloud SQL. Filter literals are the Google-listed types, not `NUMERIC` / `BIGNUMERIC` / `TIME` / `BYTES`. When normalization requires source expressions, pushdown cannot be assumed.

## 16. Why not ordinary dbt sources?

A Cloud SQL relation referenced only through `EXTERNAL_QUERY` is not an ordinary BigQuery relation. Modeling it as a normal `source()` with a fake BigQuery `database`/`schema` can create misleading relation lookup, catalog, freshness, grant, and quoting semantics.

v0.1 recommended boundary:

```text
remote table
    ↓ federated_relation()   # pins in vars
base/staging dbt model
    ↓ ref()
normal dbt DAG
```

This does **not** forbid a later `federated_relation(from_source=...)` helper that reads `source.meta` and pinned columns from `sources.yml`. That is a follow-on RFC. Spanner external datasets remain ordinary BigQuery sources and are out of this compiler.

## 17. Spanner

Out of v0.1. Existing Spanner external datasets should remain normal BigQuery relations. An `EXTERNAL_QUERY` Spanner backend can be proposed later.

## 18. Operational and security requirements

### Locations

The BigQuery query processing location SHOULD match the location encoded in the connection resource ID (`projects/.../locations/LOCATION/connections/...`). v0.1 does not fail compilation on a mismatch (the package test target is Postgres and has no BigQuery location). Operators must align locations in GCP; the compiler does not enforce it.

### Quotas and load

Google documents:

- at most 10 unique connections in one federated query;
- a cross-region federated-query bytes quota;
- `maximum bytes billed` is not supported for federated queries.

Isolate Cloud SQL from federated load with a read replica. v0.1 compile does not add compile-time federated load and does not enforce these quotas.

### Credentials

Package vars contain BigQuery connection resource IDs, not database passwords. The package stores connection IDs only and cannot enforce a read-only Cloud SQL user.

### SQL injection boundary

High-level APIs MUST distinguish identifiers, typed literals, and trusted raw SQL.

- Identifiers are **always** PostgreSQL-quoted: double quotes, with internal double quotes doubled. There is no unquoted-if-safe path in v0.1 (no `^[a-z_][a-z0-9_]*$` exception).
- High-level APIs never concatenate raw SQL fragments from the user.
- `external_query` is documented as: the dbt identity executes this string on the remote DB.

### Compiled artifacts

Compiled SQL will contain connection resource names and remote schema/table names. Documentation should warn that dbt `target/`, logs, and CI artifacts may contain rendered remote SQL.

## 19. Performance principles

1. Preserve `SELECT * FROM T` whenever correct.
2. Prefer a query-wide `bignumeric` option over per-column casts when remaining native decimals need it, including a mix of NUMERIC-fit and BIGNUMERIC-fit siblings after offender casts. Never emit `"numeric"`.
3. Do not query `information_schema` at compile time in v0.1.
4. Do not promise metadata caching.
5. Benchmark source load and bytes transferred in a later RFC that has GCP E2E; v0.1 does not claim runtime performance numbers.

## 20. Codegen and pinned workflow

v0.1 pins are hand-authored YAML in vars. A `run-operation` that prints YAML is not a reproducibility system and is not shipped as `generate_federated_models`.

`federation_inspect` prints the plan for a pin so reviewers can see conversions before merge.

## 21. dbt v1/v2 compatibility

```text
required CI:
  Core 1.10 + postgres target (Jinja engine)
  Core 1.11 + postgres target (Jinja engine)

preview (non-blocking):
  dbt Fusion + postgres target
```

Fusion BigQuery is Preview and is **not** a v0.1 acceptance gate. Do not advertise Fusion BigQuery support.

Implementation MUST avoid:

- Python adapter internals;
- compile-time database access from `federated_relation`;
- nonexistent/dynamically unresolved macros;
- custom materialization internals;
- v1-only deprecated Jinja behavior.

## 22. Testing strategy

### Layer 1: static/parse

Jinja/YAML, package namespace, parse-safe planning from pins. Core 1.10/1.11. Fusion preview optional.

### Layer 2: planner/rendering fixtures (required, no GCP)

Feed pinned column fixtures into the planner and assert plans/SQL **strings**. Never `run_query` of `EXTERNAL_QUERY`.

Required cases:

- all-native → `select * from "<schema>"."<table>"` and no options JSON;
- `uuid` / `jsonb` under `safe` → projection with `cast(... as text)`;
- `uuid` under `strict` → error unless override;
- unknown extension type → error;
- all `numeric(12,2)` → passthrough, no option;
- mix `numeric(12,2)` + unbounded `numeric` under `safe` → projection only on the unbounded column; fitting column uncast; pushdown lost;
- remaining native decimals that mix NUMERIC-fit and BIGNUMERIC-fit after offender casts → `decimal_option=bignumeric`; never emit `"numeric"`;
- same mix under `strict` → error;
- type override for uuid → remote_cast;
- missing pin → error;
- parse-equivalent planning (helper, no warehouse).

### Layer 3: source-dialect tests

Postgres container remains for the macro runner. Optional later: execute remote `cast` / quoting SQL against local Postgres. Not full federation.

### Layer 4: Google Cloud E2E

Out of v0.1 acceptance. Requires BigQuery connections and real Cloud SQL. Later RFC.

## 23. Diagnostics

Inspect output MUST expose:

- provider and connection alias;
- relation;
- type policy;
- body class and decimal option;
- converted columns;
- lossiness;
- whether the passthrough fast path survived (`pushdown=kept|lost`).

Errors MUST identify provider, table, column, raw source type, policy, and the override path needed to resolve the issue.

## 24. Target repository structure

Do **not** use `macros/public/` (this template groups by family; public macros dispatch from the family file). Do not name provider files `postgres.sql` (looks like `postgres__*` adapter impls).

```text
macros/
  federated_relation.sql
  external_query.sql
  federation/
    config.sql
    pins.sql
    plan.sql
    render.sql
    inspect.sql
    providers/
      router.sql
      cloud_sql_postgres.sql
  properties.yml

integration_tests/
  macros/tests/          # mirrored test_ files
  models/example/        # GCP-free dbt build
  models/federation/     # compile-only federated smoke

docs/rfcs/
  0001-bigquery-federation-architecture.md
```

Two-layer dispatch: public macros `adapter.dispatch` for consumer `search_order`; remote dialect via explicit router with every branch present at parse.

## 25. Implementation sequence

### Phase 0 — identity, keep Postgres runner

Rename the package to `dbt_bigquery_federation`. Drop DuckDB as a dbt target. Keep the Postgres service and Compose file. Make Fusion non-blocking.

### Phase 1 — v0.1 planner (this RFC's implementation)

Config, quoting, private renderer, `external_query`, pins, decision table, `federated_relation`, `federation_inspect`, fixture tests, compile-only federated model smoke.

### Later RFCs

MySQL, AlloyDB as a tested provider, Spanner, live opt-in discovery, schema diff, codegen, GCP E2E, Fusion BigQuery support, `source()` integration.

## 26. Acceptance criteria (v0.1)

- pinned planning for `cloud_sql_postgres`;
- documented handling or deliberate failure for known unsupported PostgreSQL types;
- per-column and per-type overrides;
- precision-aware decimal fold that does not stringify well-typed decimals because of a sibling offender;
- observable passthrough vs projection (`pushdown=kept|lost`);
- correct PostgreSQL identifier quoting;
- Core 1.10 and 1.11 CI on the Postgres Jinja engine;
- Fusion lane may fail without blocking v0.1;
- no warehouse access from `federated_relation`;
- parse emits the real planned SQL;
- stock dbt view/table/incremental remain the persistence story;
- canonical connection IDs;
- no database credentials in package configuration;
- no GCP required to merge planner work.

## 27. Major risks

| Risk | Mitigation |
| --- | --- |
| Pins drift from the remote schema | Inspect + Git review; live mode deferred |
| Normalization disables pushdown | Passthrough/query-option fast paths; inspect `pushdown` |
| Jinja planner becomes unreviewable | Decision table + fold only; no Plan D |
| Fusion parses differently | Parse-resolvable router; Fusion non-blocking |
| Type conversion loses semantics | Lossiness model, strict policy, STRING fallback |
| Raw remote SQL is unsafe | Structured high-level API; hatch is explicit |
| Fake five-provider support | v0.1 is Cloud SQL PostgreSQL only |

## 28. Closed questions and later RFCs

Closed for v0.1:

1. **Pinned store:** `vars.dbt_bigquery_federation.tables['<connection>.<schema>.<table>'].columns`. Not macro arguments, not generated `properties.yml`.
2. **Compile/docs I/O:** none. `federation_inspect` plans from pins. `live=true` errors in v0.1.
3. **Memoization:** not needed; the compiler does not query.
4. **Default metadata mode:** pinned. There is no live default.

Later RFCs:

- MySQL `TIME` mapping;
- BigQuery post-process (STRING → JSON);
- user-defined providers;
- Spanner external-dataset backend;
- `federated_relation(from_source=...)`;
- live opt-in discovery and command policy;
- AlloyDB as a separately tested provider.

## 29. Final recommendation

Implement `dbt_bigquery_federation` as a **pinned federation planner**, not a live catalog crawler, not merely an `EXTERNAL_QUERY` wrapper, and not a materialization.

The primary runtime experience should remain:

```sql
select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
```

The key implementation rules are:

> **Do not generate explicit per-column remote SQL merely because metadata is available. Generate it only when correctness or an explicit user request requires it.**

> **Do not call `run_query` from `federated_relation`. Pins are the compiler input.**

Those rules preserve BigQuery federation optimization when possible and keep dbt compilation a function of Git + vars.

## 30. References

Platform facts were rechecked against official documentation on 2026-08-14.

### dbt

- v2 upgrade/package compatibility: <https://docs.getdbt.com/docs/dbt-versions/core-upgrade/upgrading-to-v2>
- Fusion availability (BigQuery Preview): <https://docs.getdbt.com/docs/fusion/fusion-availability>
- `run_query`: <https://docs.getdbt.com/reference/dbt-jinja-functions/run_query>
- materializations: <https://docs.getdbt.com/docs/build/materializations>
- incremental models: <https://docs.getdbt.com/docs/build/incremental-models>
- dispatch: <https://docs.getdbt.com/reference/dbt-jinja-functions/dispatch?version=1.12>

### Google Cloud

- federation overview, regions, quotas, limitations, pushdown: <https://docs.cloud.google.com/bigquery/docs/federated-queries-intro>
- `EXTERNAL_QUERY`, options, type mappings: <https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/federated_query_functions>
- BigQuery data types: <https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types>
- Cloud SQL federation: <https://docs.cloud.google.com/bigquery/docs/cloud-sql-federated-queries>
