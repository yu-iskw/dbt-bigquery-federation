{% macro federation_inspect(connection, schema, table, live=false) -%}
  {{ return(adapter.dispatch('federation_inspect', 'dbt_bigquery_federation')(connection, schema, table, live)) }}
{%- endmacro %}

{% macro default__federation_inspect(connection, schema, table, live=false) -%}
  {% if live %}
    {{ exceptions.raise_compiler_error('live metadata is not implemented in v0.1; federation_inspect plans from pins only') }}
  {% endif %}
  {% set result = dbt_bigquery_federation._federation_inspect_result(connection, schema, table) %}
  {% if not result.ok %}
    {{ exceptions.raise_compiler_error(result.error) }}
  {% endif %}
  {% do log(result.report, info=True) %}
  {{ return(result.report) }}
{%- endmacro %}

{% macro _federation_inspect_result(connection, schema, table) %}
  {% set planned = dbt_bigquery_federation._federation_try_plan(connection, table, schema) %}
  {% if not planned.ok %}
    {{ return({'ok': false, 'error': planned.error, 'report': none, 'plan': none}) }}
  {% endif %}
  {% set plan = planned.plan %}
  {% set decimal_label = plan.decimal_option if plan.decimal_option else 'none' %}
  {% set lines = namespace(rows=[
    'provider=' ~ plan.provider,
    'connection=' ~ plan.connection,
    'relation=' ~ plan.schema ~ '.' ~ plan.table,
    'policy=' ~ plan.policy,
    'body=' ~ plan.body,
    'decimal_option=' ~ decimal_label,
    'pushdown=' ~ plan.pushdown,
    '',
    'COLUMN\tSOURCE TYPE\tTARGET\tACTION\tLOSSINESS\tPUSHDOWN'
  ]) %}
  {% for col in plan.columns %}
    {% set lines.rows = lines.rows + [
      col.name ~ '\t' ~ col.source_type ~ '\t' ~ col.target_type ~ '\t' ~ col.action ~ '\t' ~ col.lossiness ~ '\t' ~ plan.pushdown
    ] %}
  {% endfor %}
  {{ return({'ok': true, 'error': none, 'plan': plan, 'report': lines.rows | join('\n')}) }}
{% endmacro %}
