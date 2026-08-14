{% macro federation_inspect(connection, schema, table, live=false, type_policy=None, overrides=None) -%}
  {{ return(adapter.dispatch('federation_inspect', 'dbt_bigquery_federation')(connection, schema, table, live, type_policy, overrides)) }}
{%- endmacro %}

{% macro default__federation_inspect(connection, schema, table, live=false, type_policy=None, overrides=None) -%}
  {% set result = dbt_bigquery_federation._federation_inspect_result(connection, schema, table, live, type_policy, overrides) %}
  {% if not result.ok %}
    {{ exceptions.raise_compiler_error(result.error) }}
  {% endif %}
  {% do log(result.report, info=True) %}
  {{ return(result.report) }}
{%- endmacro %}

{% macro _federation_inspect_result(connection, schema, table, live=false, type_policy=None, overrides=None) %}
  {% if live %}
    {{ return({
      'ok': false,
      'error': 'live metadata is not implemented in v0.1; federation_inspect plans from pins only',
      'report': none,
      'plan': none
    }) }}
  {% endif %}
  {% set planned = dbt_bigquery_federation._federation_try_plan(connection, table, schema, type_policy, overrides) %}
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
    {% set col_pushdown = 'lost' if col.action == 'remote_cast' else 'kept' %}
    {% do lines.rows.append(
      col.name ~ '\t' ~ col.source_type ~ '\t' ~ col.target_type ~ '\t' ~ col.action ~ '\t' ~ col.lossiness ~ '\t' ~ col_pushdown
    ) %}
  {% endfor %}
  {{ return({'ok': true, 'error': none, 'plan': plan, 'report': lines.rows | join('\n')}) }}
{% endmacro %}
