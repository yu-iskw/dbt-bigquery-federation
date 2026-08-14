# Macros directory

## Layout

- Group related macros by folder (for example `federation/`).
- **One primary `.sql` file per public macro family**, named after the public macro (for example `federated_relation.sql`).
- Put the **dispatcher**, **`default__*`**, and any adapter-specific implementations **in that same file**.
- Remote-provider helpers live under `federation/providers/` and are selected by an explicit router, not `adapter.dispatch`.

## Dispatch (required for public macros)

Every public macro that should be overridable must:

1. Define a thin dispatcher whose only job is to call `adapter.dispatch` with **string literals** for `macro_name` and `macro_namespace`.
2. Use `macro_namespace: 'dbt_bigquery_federation'` — it **must** match `name` in the root [`dbt_project.yml`](../dbt_project.yml).

Pattern:

```jinja
{% macro my_macro(arg) -%}
  {{ return(adapter.dispatch('my_macro', 'dbt_bigquery_federation')(arg)) }}
{%- endmacro %}

{% macro default__my_macro(arg) -%}
  {# shared implementation; this package emits BigQuery SQL #}
{%- endmacro %}
```

Do **not** add `postgres__federated_relation`. The dbt target adapter is not the remote database. Remote Cloud SQL PostgreSQL quoting and type maps go through `federation/providers/router.sql`.

Internal helpers (`_federation_*`, `_cloud_sql_postgres_*`) must be called with the package prefix:

```jinja
{% set result = dbt_bigquery_federation._federation_try_plan(connection, table, schema) %}
```

dbt only flattens macros from the **current node’s package** and the **root project** into the top-level Jinja namespace. Package helpers are otherwise available only as `dbt_bigquery_federation.<name>`. Consumer models that compile `federated_relation` execute `default__*` in that flattened context, so unprefixed helper names resolve as undefined.

Reference: [About dispatch config](https://docs.getdbt.com/reference/dbt-jinja-functions/dispatch?version=1.12).

## dbt docs (macro properties)

- Document **public** macros in [`properties.yml`](properties.yml) at the `macros/` root. dbt merges resource properties.
- Use the **dispatcher** macro `name` in YAML (for example `federated_relation`), not `default__federated_relation`.
- Keep `arguments` aligned with the Jinja signature.

## Tests

Macro unit tests mirror this tree under [`integration_tests/macros/tests/`](../integration_tests/macros/tests/) (see [`integration_tests/CLAUDE.md`](../integration_tests/CLAUDE.md)). Planner tests MUST assert SQL strings and MUST NOT `run_query` `EXTERNAL_QUERY`.
