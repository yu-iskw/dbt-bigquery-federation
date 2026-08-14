# Macros

Package macros for pinned BigQuery `EXTERNAL_QUERY` planning.

Public entrypoints:

- [`federated_relation.sql`](federated_relation.sql) — table-expression planner
- [`external_query.sql`](external_query.sql) — trusted raw SQL hatch
- [`federation/inspect.sql`](federation/inspect.sql) — `federation_inspect` run-operation

Internal helpers live under [`federation/`](federation/). Conventions for dispatch and file layout are in [`CLAUDE.md`](CLAUDE.md).

Macro descriptions and arguments for **dbt docs** live in [`properties.yml`](properties.yml).
