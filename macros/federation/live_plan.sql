{% macro _federation_try_plan_columns(connection_cfg, schema, table, columns, type_policy=None, overrides=None) %}
  {% set relation = connection_cfg.provider ~ ' ' ~ schema ~ '.' ~ table %}
  {% set policy_result = dbt_bigquery_federation._federation_resolve_policy(connection_cfg, type_policy) %}
  {% if not policy_result.ok %}
    {{ return({'ok': false, 'error': relation ~ ': ' ~ policy_result.error, 'plan': none}) }}
  {% endif %}
  {% set policy = policy_result.policy %}
  {% set type_overrides = dbt_bigquery_federation._federation_package_type_overrides(connection_cfg.provider) %}
  {% if overrides is none %}
    {% set invocation_overrides = {} %}
  {% elif overrides is mapping %}
    {% set invocation_overrides = overrides %}
  {% else %}
    {{ return({'ok': false, 'error': relation ~ ': overrides must be a mapping', 'plan': none}) }}
  {% endif %}

  {% set classified_ns = namespace(columns=[]) %}
  {% for column in columns %}
    {% set item = dbt_bigquery_federation._federation_classify_column(connection_cfg.provider, column, policy, type_overrides, invocation_overrides) %}
    {% if not item.ok %}
      {{ return({'ok': false, 'error': relation ~ ': ' ~ item.error, 'plan': none}) }}
    {% endif %}
    {% do classified_ns.columns.append(item.classified) %}
  {% endfor %}

  {% set folded = dbt_bigquery_federation._federation_fold_decimals(classified_ns.columns, policy) %}
  {% if not folded.ok %}
    {{ return({'ok': false, 'error': relation ~ ': ' ~ folded.error, 'plan': none}) }}
  {% endif %}
  {% set sql_plan = dbt_bigquery_federation._federation_build_remote_sql(connection_cfg.provider, schema, table, folded.columns) %}
  {{ return({'ok': true, 'error': none, 'plan': {
    'provider': connection_cfg.provider,
    'connection': connection_cfg.alias,
    'connection_id': connection_cfg.connection_id,
    'schema': schema,
    'table': table,
    'policy': policy,
    'body': sql_plan.body,
    'decimal_option': folded.decimal_option,
    'query_execution_priority': connection_cfg.get('query_execution_priority'),
    'pushdown': sql_plan.pushdown,
    'remote_sql': sql_plan.remote_sql,
    'warnings': folded.warnings,
    'columns': folded.columns,
    'metadata_source': 'live'
  }}) }}
{% endmacro %}

{% macro _federation_try_plan_live(connection, table, schema=None, type_policy=None, overrides=None) %}
  {% set discovered = dbt_bigquery_federation._federation_try_get_remote_columns(connection, table, schema) %}
  {% if not discovered.ok %}
    {{ return({'ok': false, 'error': discovered.error, 'plan': none}) }}
  {% endif %}
  {{ return(dbt_bigquery_federation._federation_try_plan_columns(discovered.connection, discovered.schema, discovered.table, discovered.columns, type_policy, overrides)) }}
{% endmacro %}
