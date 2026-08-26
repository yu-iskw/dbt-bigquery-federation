{% macro federated_relation(connection, table, schema=None, type_policy=None, overrides=None, metadata_mode=None) -%}
  {{ return(adapter.dispatch('federated_relation', 'dbt_bigquery_federation')(connection, table, schema, type_policy, overrides, metadata_mode)) }}
{%- endmacro %}

{% macro default__federated_relation(connection, table, schema=None, type_policy=None, overrides=None, metadata_mode=None) -%}
  {# Compat: reject live/auto. Models are pin-only; discovery is run-operation. #}
  {% if metadata_mode is not none %}
    {% set mode = metadata_mode | string | lower | trim %}
    {% if mode != 'pinned' %}
      {{ exceptions.raise_compiler_error(
        "federated_relation does not support metadata_mode='" ~ mode ~ "'. Models always plan from vars.dbt_bigquery_federation.tables pins. Use run-operation federation_inspect / federation_generate_pin / federation_validate for live discovery."
      ) }}
    {% endif %}
  {% endif %}

  {% set result = dbt_bigquery_federation._federation_try_plan(connection, table, schema, type_policy, overrides) %}
  {% if not result.ok %}{{ exceptions.raise_compiler_error(result.error) }}{% endif %}
  {% for warning in result.plan.warnings %}{% do exceptions.warn(warning) %}{% endfor %}
  {{ return(dbt_bigquery_federation._federation_render_external_query(
    result.plan.connection_id,
    result.plan.remote_sql,
    result.plan.decimal_option,
    result.plan.get('query_execution_priority')
  )) }}
{%- endmacro %}
