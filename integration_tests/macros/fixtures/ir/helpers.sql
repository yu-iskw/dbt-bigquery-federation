{# Shared helpers for normalized column IR fixture packs.
   Layer-2 planner tests call _federation_try_plan_columns with these packs;
   they must not run_query or live-discover remote schemas. #}

{% macro _ir_fixture_connection(provider, alias, connection_id, policy='safe', query_execution_priority=none) %}
  {{ return({
    'provider': provider,
    'alias': alias,
    'connection_id': connection_id,
    'policy': policy,
    'query_execution_priority': query_execution_priority
  }) }}
{% endmacro %}

{% macro _ir_fixture_column_names(fixture) %}
  {% set names = [] %}
  {% for col in fixture.columns %}
    {% do names.append(col.name) %}
  {% endfor %}
  {{ return(names) }}
{% endmacro %}

{% macro _ir_fixture_plan(fixture, type_policy=none, overrides=none, metadata_source='live') %}
  {{ return(dbt_bigquery_federation._federation_try_plan_columns(
    fixture.connection,
    fixture.schema,
    fixture.table,
    fixture.columns,
    type_policy,
    overrides,
    metadata_source
  )) }}
{% endmacro %}

{% macro _ir_fixture_assert_column_action(plan, column_name, expected_action) %}
  {% set matched = namespace(found=false) %}
  {% for col in plan.columns %}
    {% if (col.name | string | lower) == (column_name | lower) %}
      {% set matched.found = true %}
      {% do dbt_unittest.assert_equals(col.action, expected_action) %}
    {% endif %}
  {% endfor %}
  {% do dbt_unittest.assert_equals(matched.found, true) %}
{% endmacro %}
