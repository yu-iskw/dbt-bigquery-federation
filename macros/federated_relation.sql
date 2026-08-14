{% macro federated_relation(connection, table, schema=None, type_policy=None, overrides=None, metadata_mode=None) -%}
  {{ return(adapter.dispatch('federated_relation', 'dbt_bigquery_federation')(connection, table, schema, type_policy, overrides, metadata_mode)) }}
{%- endmacro %}

{% macro default__federated_relation(connection, table, schema=None, type_policy=None, overrides=None, metadata_mode=None) -%}
  {% set mode_result = dbt_bigquery_federation._federation_resolve_metadata_mode(connection, table, schema, metadata_mode) %}
  {% if not mode_result.ok %}{{ exceptions.raise_compiler_error(mode_result.error) }}{% endif %}

  {% if mode_result.mode == 'live' and not execute %}
    {% set stub = dbt_bigquery_federation._federation_parse_stub(connection, table, schema) %}
    {% if not stub.ok %}{{ exceptions.raise_compiler_error(stub.error) }}{% endif %}
    {{ return(stub.sql) }}
  {% endif %}

  {% if mode_result.mode == 'live' %}
    {% set result = dbt_bigquery_federation._federation_try_plan_live(connection, table, schema, type_policy, overrides) %}
  {% else %}
    {% set result = dbt_bigquery_federation._federation_try_plan(connection, table, schema, type_policy, overrides) %}
  {% endif %}
  {% if not result.ok %}{{ exceptions.raise_compiler_error(result.error) }}{% endif %}
  {% for warning in result.plan.warnings %}{% do exceptions.warn(warning) %}{% endfor %}
  {{ return(dbt_bigquery_federation._federation_render_external_query(
    result.plan.connection_id,
    result.plan.remote_sql,
    result.plan.decimal_option,
    result.plan.get('query_execution_priority')
  )) }}
{%- endmacro %}
