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
    {% set planned = dbt_bigquery_federation._federation_try_plan_live(connection, table, schema, type_policy, overrides) %}
    {% set metadata_source = 'live' %}
  {% else %}
    {% set planned = dbt_bigquery_federation._federation_try_plan(connection, table, schema, type_policy, overrides) %}
    {% set metadata_source = 'pinned' %}
  {% endif %}
  {% if not planned.ok %}
    {{ return({'ok': false, 'error': planned.error, 'report': none, 'plan': none}) }}
  {% endif %}
  {% set plan = planned.plan %}
  {% set decimal_label = plan.decimal_option if plan.decimal_option else 'none' %}
  {% set lines = namespace(rows=[
    'provider=' ~ plan.provider,
    'connection=' ~ plan.connection,
    'relation=' ~ plan.schema ~ '.' ~ plan.table,
    'metadata_source=' ~ metadata_source,
    'policy=' ~ plan.policy,
    'body=' ~ plan.body,
    'decimal_option=' ~ decimal_label,
    'pushdown=' ~ plan.pushdown,
    '',
    'COLUMN\tSOURCE TYPE\tTARGET\tACTION\tLOSSINESS\tREMOTE EXPRESSION'
  ]) %}
  {% for col in plan.columns %}
    {% set remote_expr = 'yes' if col.action == 'remote_cast' else 'no' %}
    {% do lines.rows.append(
      col.name ~ '\t' ~ col.source_type ~ '\t' ~ col.target_type ~ '\t' ~ col.action ~ '\t' ~ col.lossiness ~ '\t' ~ remote_expr
    ) %}
  {% endfor %}
  {{ return({'ok': true, 'error': none, 'plan': plan, 'report': lines.rows | join('\n')}) }}
{% endmacro %}
