{% macro federated_relation(connection, table, schema=None, type_policy=None, overrides=None) -%}
  {{ return(adapter.dispatch('federated_relation', 'dbt_bigquery_federation')(connection, table, schema, type_policy, overrides)) }}
{%- endmacro %}

{% macro default__federated_relation(connection, table, schema=None, type_policy=None, overrides=None) -%}
  {% set result = dbt_bigquery_federation._federation_try_plan(connection, table, schema, type_policy, overrides) %}
  {% if not result.ok %}
    {{ exceptions.raise_compiler_error(result.error) }}
  {% endif %}
  {{ return(dbt_bigquery_federation._render_external_query(result.plan.connection_id, result.plan.remote_sql, result.plan.decimal_option)) }}
{%- endmacro %}
