{% macro federation_generate_pin(connection, table, schema=None) -%}
  {{ return(adapter.dispatch('federation_generate_pin', 'dbt_bigquery_federation')(connection, table, schema)) }}
{%- endmacro %}

{% macro default__federation_generate_pin(connection, table, schema=None) -%}
  {% set result = dbt_bigquery_federation._federation_try_get_remote_columns(connection, table, schema) %}
  {% if not result.ok %}
    {{ exceptions.raise_compiler_error(result.error) }}
  {% endif %}
  {% set key = dbt_bigquery_federation._federation_pin_key(connection, result.schema, table) %}
  {% set lines = namespace(rows=['tables:', '  ' ~ key ~ ':', '    columns:']) %}
  {% for col in result.columns %}
    {% do lines.rows.append('      - name: ' ~ dbt_bigquery_federation._federation_yaml_double_quoted(col.name)) %}
    {% set declared = dbt_bigquery_federation._federation_column_declared_type(col) %}
    {% do lines.rows.append('        data_type: ' ~ dbt_bigquery_federation._federation_yaml_double_quoted(declared)) %}
    {% if dbt_bigquery_federation._federation_type_carries_numeric_typmod(declared) %}
      {% if col.precision is not none %}
        {% do lines.rows.append('        precision: ' ~ (col.precision | string)) %}
      {% endif %}
      {% if col.scale is not none %}
        {% do lines.rows.append('        scale: ' ~ (col.scale | string)) %}
      {% endif %}
    {% endif %}
    {% if dbt_bigquery_federation._federation_type_carries_length_typmod(declared) and col.character_maximum_length is not none %}
      {% do lines.rows.append('        character_maximum_length: ' ~ (col.character_maximum_length | string)) %}
    {% endif %}
  {% endfor %}
  {% set rendered = lines.rows | join('\n') %}
  {% do log(rendered, info=True) %}
  {{ return(rendered) }}
{%- endmacro %}

{% macro _federation_yaml_double_quoted(value) %}
  {% set text = value | string %}
  {% set escaped = text
    | replace('\\', '\\\\')
    | replace('"', '\\"')
    | replace('\n', '\\n')
    | replace('\r', '\\r')
  %}
  {{ return('"' ~ escaped ~ '"') }}
{% endmacro %}

{% macro _federation_column_comparable_type(column, provider=none) %}
  {% set declared = dbt_bigquery_federation._federation_column_declared_type(column) %}
  {% if provider is none %}
    {{ return(declared | string | lower | trim) }}
  {% endif %}
  {{ return(dbt_bigquery_federation._federation_provider_normalize_type_name(provider, declared)) }}
{% endmacro %}

{% macro _federation_column_signature(column, provider=none) %}
  {% set data_type = dbt_bigquery_federation._federation_column_comparable_type(column, provider) %}
  {% set numeric = dbt_bigquery_federation._federation_type_carries_numeric_typmod(data_type) %}
  {% set length = dbt_bigquery_federation._federation_type_carries_length_typmod(data_type) %}
  {{ return({
    'data_type': data_type | string | lower | trim,
    'precision': column.get('precision') if numeric else none,
    'scale': column.get('scale') if numeric else none,
    'character_maximum_length': column.get('character_maximum_length') if length else none
  }) }}
{% endmacro %}

{% macro _federation_format_column_type(column, provider=none) %}
  {% set data_type = dbt_bigquery_federation._federation_column_comparable_type(column, provider) %}
  {% if dbt_bigquery_federation._federation_type_carries_numeric_typmod(data_type) and column.get('precision') is not none and column.get('scale') is not none %}
    {{ return(data_type ~ '(' ~ (column.precision | string) ~ ',' ~ (column.scale | string) ~ ')') }}
  {% endif %}
  {% if dbt_bigquery_federation._federation_type_carries_length_typmod(data_type) and column.get('character_maximum_length') is not none %}
    {{ return(data_type ~ '(' ~ (column.character_maximum_length | string) ~ ')') }}
  {% endif %}
  {{ return(data_type) }}
{% endmacro %}

{% macro _federation_schema_diff_columns(pinned_columns, live_columns, provider=none) %}
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
    {% elif dbt_bigquery_federation._federation_column_signature(pinned.map[name], provider) != dbt_bigquery_federation._federation_column_signature(live.map[name], provider) %}
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

{% macro _federation_format_schema_diff_report(schema, table, diff, provider=none) %}
  {% set lines = namespace(rows=['relation=' ~ schema ~ '.' ~ table]) %}
  {% for col in diff.added %}
    {% do lines.rows.append('+ ' ~ col.name ~ ' ' ~ dbt_bigquery_federation._federation_format_column_type(col, provider)) %}
  {% endfor %}
  {% for col in diff.removed %}
    {% do lines.rows.append('- ' ~ col.name ~ ' ' ~ dbt_bigquery_federation._federation_format_column_type(col, provider)) %}
  {% endfor %}
  {% for item in diff.changed %}
    {% do lines.rows.append(
      '~ ' ~ item.name ~ ' ' ~ dbt_bigquery_federation._federation_format_column_type(item.pinned, provider)
      ~ ' -> ' ~ dbt_bigquery_federation._federation_format_column_type(item.live, provider)
    ) %}
  {% endfor %}
  {% if not diff.has_changes %}
    {% do lines.rows.append('no changes') %}
  {% endif %}
  {{ return(lines.rows | join('\n')) }}
{% endmacro %}

{% macro _federation_try_pin_live_diff(connection, table, schema=None) %}
  {% set pin = dbt_bigquery_federation._federation_try_load_pin(connection, table, schema) %}
  {% if not pin.ok %}
    {{ return({'ok': false, 'error': pin.error, 'diff': none, 'schema': none, 'table': table, 'provider': none}) }}
  {% endif %}
  {% set live = dbt_bigquery_federation._federation_try_get_remote_columns(connection, table, schema) %}
  {% if not live.ok %}
    {{ return({'ok': false, 'error': live.error, 'diff': none, 'schema': none, 'table': table, 'provider': none}) }}
  {% endif %}
  {{ return({
    'ok': true,
    'error': none,
    'diff': dbt_bigquery_federation._federation_schema_diff_columns(pin.pin.columns, live.columns, pin.connection.provider),
    'schema': live.schema,
    'table': table,
    'provider': pin.connection.provider
  }) }}
{% endmacro %}

{% macro federation_schema_diff(connection, table, schema=None) -%}
  {{ return(adapter.dispatch('federation_schema_diff', 'dbt_bigquery_federation')(connection, table, schema)) }}
{%- endmacro %}

{% macro default__federation_schema_diff(connection, table, schema=None) -%}
  {% set result = dbt_bigquery_federation._federation_try_pin_live_diff(connection, table, schema) %}
  {% if not result.ok %}
    {{ exceptions.raise_compiler_error(result.error) }}
  {% endif %}
  {% set report = dbt_bigquery_federation._federation_format_schema_diff_report(result.schema, table, result.diff, result.provider) %}
  {% do log(report, info=True) %}
  {{ return(report) }}
{%- endmacro %}

{% macro federation_validate(connection, table, schema=None, fail_on_drift=true) -%}
  {{ return(adapter.dispatch('federation_validate', 'dbt_bigquery_federation')(connection, table, schema, fail_on_drift)) }}
{%- endmacro %}

{% macro default__federation_validate(connection, table, schema=None, fail_on_drift=true) -%}
  {% set result = dbt_bigquery_federation._federation_try_pin_live_diff(connection, table, schema) %}
  {% if not result.ok %}
    {{ exceptions.raise_compiler_error(result.error) }}
  {% endif %}
  {% if result.diff.has_changes and fail_on_drift %}
    {{ exceptions.raise_compiler_error(
      'Federation schema drift detected for ' ~ connection ~ '.' ~ result.schema ~ '.' ~ table ~
      ': added=' ~ (result.diff.added | length) ~ ', removed=' ~ (result.diff.removed | length) ~ ', changed=' ~ (result.diff.changed | length)
    ) }}
  {% endif %}
  {{ return(not result.diff.has_changes) }}
{%- endmacro %}
