{% macro federation_generate_pin(connection, table, schema=None) -%}
  {% set result = dbt_bigquery_federation._federation_try_get_remote_columns(connection, table, schema) %}
  {% if not result.ok %}
    {{ exceptions.raise_compiler_error(result.error) }}
  {% endif %}
  {% set key = dbt_bigquery_federation._federation_pin_key(connection, result.schema, table) %}
  {% set lines = namespace(rows=['tables:', '  ' ~ key ~ ':', '    columns:']) %}
  {% for col in result.columns %}
    {% do lines.rows.append('      - name: ' ~ col.name) %}
    {% do lines.rows.append('        data_type: ' ~ col.data_type) %}
    {% if col.precision is not none %}
      {% do lines.rows.append('        precision: ' ~ (col.precision | string)) %}
    {% endif %}
    {% if col.scale is not none %}
      {% do lines.rows.append('        scale: ' ~ (col.scale | string)) %}
    {% endif %}
  {% endfor %}
  {% set rendered = lines.rows | join('\n') %}
  {% do log(rendered, info=True) %}
  {{ return(rendered) }}
{%- endmacro %}

{% macro _federation_column_signature(column) %}
  {{ return({
    'data_type': column.get('data_type'),
    'precision': column.get('precision'),
    'scale': column.get('scale')
  }) }}
{% endmacro %}

{% macro _federation_schema_diff_columns(pinned_columns, live_columns) %}
  {% set pinned = namespace(map={}, order=[]) %}
  {% set live = namespace(map={}, order=[]) %}
  {% for col in pinned_columns %}
    {% do pinned.map.update({col.name: col}) %}
    {% do pinned.order.append(col.name) %}
  {% endfor %}
  {% for col in live_columns %}
    {% do live.map.update({col.name: col}) %}
    {% do live.order.append(col.name) %}
  {% endfor %}
  {% set diff = namespace(added=[], removed=[], changed=[]) %}
  {% for name in live.order %}
    {% if name not in pinned.map %}
      {% do diff.added.append(live.map[name]) %}
    {% elif dbt_bigquery_federation._federation_column_signature(pinned.map[name]) != dbt_bigquery_federation._federation_column_signature(live.map[name]) %}
      {% do diff.changed.append({'name': name, 'pinned': pinned.map[name], 'live': live.map[name]}) %}
    {% endif %}
  {% endfor %}
  {% for name in pinned.order %}
    {% if name not in live.map %}
      {% do diff.removed.append(pinned.map[name]) %}
    {% endif %}
  {% endfor %}
  {{ return({'added': diff.added, 'removed': diff.removed, 'changed': diff.changed, 'has_changes': (diff.added | length + diff.removed | length + diff.changed | length) > 0}) }}
{% endmacro %}

{% macro federation_schema_diff(connection, table, schema=None) -%}
  {% set pin = dbt_bigquery_federation._federation_try_load_pin(connection, table, schema) %}
  {% if not pin.ok %}
    {{ exceptions.raise_compiler_error(pin.error) }}
  {% endif %}
  {% set live = dbt_bigquery_federation._federation_try_get_remote_columns(connection, table, schema) %}
  {% if not live.ok %}
    {{ exceptions.raise_compiler_error(live.error) }}
  {% endif %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pin.pin.columns, live.columns) %}
  {% set lines = namespace(rows=['relation=' ~ live.schema ~ '.' ~ table]) %}
  {% for col in diff.added %}
    {% do lines.rows.append('+ ' ~ col.name ~ ' ' ~ col.data_type) %}
  {% endfor %}
  {% for col in diff.removed %}
    {% do lines.rows.append('- ' ~ col.name ~ ' ' ~ col.data_type) %}
  {% endfor %}
  {% for item in diff.changed %}
    {% do lines.rows.append('~ ' ~ item.name ~ ' ' ~ item.pinned.data_type ~ ' -> ' ~ item.live.data_type) %}
  {% endfor %}
  {% if not diff.has_changes %}
    {% do lines.rows.append('no changes') %}
  {% endif %}
  {% set report = lines.rows | join('\n') %}
  {% do log(report, info=True) %}
  {{ return(report) }}
{%- endmacro %}

{% macro federation_validate(connection, table, schema=None, fail_on_drift=true) -%}
  {% set pin = dbt_bigquery_federation._federation_try_load_pin(connection, table, schema) %}
  {% if not pin.ok %}
    {{ exceptions.raise_compiler_error(pin.error) }}
  {% endif %}
  {% set live = dbt_bigquery_federation._federation_try_get_remote_columns(connection, table, schema) %}
  {% if not live.ok %}
    {{ exceptions.raise_compiler_error(live.error) }}
  {% endif %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pin.pin.columns, live.columns) %}
  {% if diff.has_changes and fail_on_drift %}
    {{ exceptions.raise_compiler_error(
      'Federation schema drift detected for ' ~ connection ~ '.' ~ live.schema ~ '.' ~ table ~
      ': added=' ~ (diff.added | length) ~ ', removed=' ~ (diff.removed | length) ~ ', changed=' ~ (diff.changed | length)
    ) }}
  {% endif %}
  {{ return(not diff.has_changes) }}
{%- endmacro %}
