{% macro _federation_numeric_fits(precision, scale, max_precision, max_scale, max_integer_digits) %}
  {% if precision is none or scale is none %}
    {{ return(false) }}
  {% endif %}
  {% set p = precision | int %}
  {% set s = scale | int %}
  {% if p > max_precision or s > max_scale or (p - s) > max_integer_digits %}
    {{ return(false) }}
  {% endif %}
  {{ return(true) }}
{% endmacro %}

{% macro _federation_fits_numeric(precision, scale) %}
  {{ return(_federation_numeric_fits(precision, scale, 38, 9, 29)) }}
{% endmacro %}

{% macro _federation_fits_bignumeric(precision, scale) %}
  {{ return(_federation_numeric_fits(precision, scale, 76, 38, 38)) }}
{% endmacro %}

{% macro _federation_copy_column(col, action, target_type, remote_type, lossiness) %}
  {{ return({
    'name': col.name,
    'source_type': col.source_type,
    'raw_data_type': col.raw_data_type,
    'precision': col.precision,
    'scale': col.scale,
    'action': action,
    'kind': col.kind,
    'target_type': target_type,
    'remote_type': remote_type,
    'lossiness': lossiness
  }) }}
{% endmacro %}

{% macro _federation_column_name(column) %}
  {% if column is not mapping %}
    {{ return('') }}
  {% endif %}
  {{ return(column.get('name') | string) }}
{% endmacro %}

{% macro _federation_lookup_override(column, type_overrides, invocation_overrides) %}
  {% set col_name = _federation_column_name(column) %}
  {% if invocation_overrides is mapping and col_name in invocation_overrides %}
    {{ return(invocation_overrides[col_name]) }}
  {% endif %}
  {% if column is mapping and column.get('strategy') %}
    {{ return({
      'strategy': column.get('strategy'),
      'remote_type': column.get('remote_type', 'text'),
      'target_type': column.get('target_type', 'STRING')
    }) }}
  {% endif %}
  {% set data_type = _cloud_sql_postgres_normalize_type_name(column.get('data_type')) %}
  {% if type_overrides is mapping and data_type in type_overrides %}
    {{ return(type_overrides[data_type]) }}
  {% endif %}
  {% if type_overrides is mapping and column.get('data_type') in type_overrides %}
    {{ return(type_overrides[column.get('data_type')]) }}
  {% endif %}
  {{ return(none) }}
{% endmacro %}

{% macro _federation_classify_column(provider, column, policy, type_overrides, invocation_overrides) %}
  {% if column is not mapping %}
    {{ return({'ok': false, 'error': 'Each pin column must be a mapping', 'classified': none}) }}
  {% endif %}
  {% set name = column.get('name') %}
  {% if not name %}
    {{ return({'ok': false, 'error': 'Pin column is missing name', 'classified': none}) }}
  {% endif %}
  {% set data_type = column.get('data_type') %}
  {% if not data_type %}
    {{ return({'ok': false, 'error': 'Pin column ' ~ name ~ ' is missing data_type', 'classified': none}) }}
  {% endif %}
  {% set override = _federation_lookup_override(column, type_overrides, invocation_overrides) %}
  {% if override is mapping %}
    {% set strategy = override.get('strategy') | string | lower %}
    {% if strategy == 'remote_cast' %}
      {{ return({'ok': true, 'error': none, 'classified': {
        'name': name,
        'source_type': _cloud_sql_postgres_normalize_type_name(data_type),
        'raw_data_type': column.get('raw_data_type', data_type),
        'precision': column.get('precision'),
        'scale': column.get('scale'),
        'action': 'remote_cast',
        'kind': 'override',
        'target_type': override.get('target_type', 'STRING'),
        'remote_type': override.get('remote_type', 'text'),
        'lossiness': 'representation_change'
      }}) }}
    {% elif strategy == 'passthrough' %}
      {{ return({'ok': true, 'error': none, 'classified': {
        'name': name,
        'source_type': _cloud_sql_postgres_normalize_type_name(data_type),
        'raw_data_type': column.get('raw_data_type', data_type),
        'precision': column.get('precision'),
        'scale': column.get('scale'),
        'action': 'passthrough',
        'kind': 'override',
        'target_type': override.get('target_type', 'STRING'),
        'remote_type': none,
        'lossiness': override.get('lossiness', 'exact')
      }}) }}
    {% elif strategy == 'fail' %}
      {{ return({'ok': false, 'error': 'Column ' ~ name ~ ' is blocked by an explicit fail override', 'classified': none}) }}
    {% else %}
      {{ return({'ok': false, 'error': 'Unknown override strategy ' ~ strategy ~ ' for column ' ~ name, 'classified': none}) }}
    {% endif %}
  {% endif %}

  {% set entry = _federation_provider_type_entry(provider, data_type) %}
  {% if entry.kind == 'native' %}
    {{ return({'ok': true, 'error': none, 'classified': {
      'name': name,
      'source_type': entry.data_type,
      'raw_data_type': column.get('raw_data_type', data_type),
      'precision': column.get('precision'),
      'scale': column.get('scale'),
      'action': 'passthrough',
      'kind': 'native',
      'target_type': entry.target,
      'remote_type': none,
      'lossiness': entry.lossiness
    }}) }}
  {% elif entry.kind == 'decimal' %}
    {{ return({'ok': true, 'error': none, 'classified': {
      'name': name,
      'source_type': entry.data_type,
      'raw_data_type': column.get('raw_data_type', data_type),
      'precision': column.get('precision'),
      'scale': column.get('scale'),
      'action': 'decimal',
      'kind': 'decimal',
      'target_type': 'NUMERIC',
      'remote_type': none,
      'lossiness': 'exact'
    }}) }}
  {% elif entry.kind == 'unsupported' %}
    {% if policy == 'strict' %}
      {{ return({
        'ok': false,
        'error': 'Column ' ~ name ~ ' has unsupported type ' ~ entry.data_type ~ ' under strict policy. Add a type_overrides or column override with strategy=remote_cast.',
        'classified': none
      }) }}
    {% endif %}
    {{ return({'ok': true, 'error': none, 'classified': {
      'name': name,
      'source_type': entry.data_type,
      'raw_data_type': column.get('raw_data_type', data_type),
      'precision': column.get('precision'),
      'scale': column.get('scale'),
      'action': 'remote_cast',
      'kind': 'unsupported',
      'target_type': entry.target,
      'remote_type': entry.remote_type,
      'lossiness': entry.lossiness
    }}) }}
  {% endif %}
  {{ return({
    'ok': false,
    'error': 'Column ' ~ name ~ ' has unknown type ' ~ entry.data_type ~ ' under ' ~ policy ~ ' policy. Add a type override or pin strategy.',
    'classified': none
  }) }}
{% endmacro %}

{% macro _federation_fold_decimals(classified_columns, policy) %}
  {% set ns = namespace(decimals=[], others=[]) %}
  {% for col in classified_columns %}
    {% if col.kind == 'decimal' %}
      {% set ns.decimals = ns.decimals + [col] %}
    {% else %}
      {% set ns.others = ns.others + [col] %}
    {% endif %}
  {% endfor %}
  {% if ns.decimals | length == 0 %}
    {{ return({'ok': true, 'error': none, 'columns': classified_columns, 'decimal_option': none, 'warnings': []}) }}
  {% endif %}

  {% set fit = namespace(all_numeric=true, all_bignumeric=true) %}
  {% for col in ns.decimals %}
    {% if not _federation_fits_numeric(col.precision, col.scale) %}
      {% set fit.all_numeric = false %}
    {% endif %}
    {% if not _federation_fits_bignumeric(col.precision, col.scale) %}
      {% set fit.all_bignumeric = false %}
    {% endif %}
  {% endfor %}

  {% if fit.all_numeric %}
    {% set folded = namespace(columns=[]) %}
    {% for col in ns.decimals %}
      {% set folded.columns = folded.columns + [_federation_copy_column(col, 'passthrough', 'NUMERIC', none, 'exact')] %}
    {% endfor %}
    {{ return({'ok': true, 'error': none, 'columns': ns.others + folded.columns, 'decimal_option': none, 'warnings': []}) }}
  {% endif %}

  {% if fit.all_bignumeric %}
    {% set folded = namespace(columns=[]) %}
    {% for col in ns.decimals %}
      {% set folded.columns = folded.columns + [_federation_copy_column(col, 'passthrough', 'BIGNUMERIC', none, 'exact')] %}
    {% endfor %}
    {{ return({'ok': true, 'error': none, 'columns': ns.others + folded.columns, 'decimal_option': 'bignumeric', 'warnings': []}) }}
  {% endif %}

  {% if policy == 'strict' %}
    {% set offenders = namespace(names=[]) %}
    {% for col in ns.decimals %}
      {% if not _federation_fits_bignumeric(col.precision, col.scale) %}
        {% set offenders.names = offenders.names + [col.name] %}
      {% endif %}
    {% endfor %}
    {{ return({
      'ok': false,
      'error': 'Decimal columns are unbounded or exceed BIGNUMERIC under strict policy: ' ~ (offenders.names | join(', ')) ~ '. Add an override or tighten the pin precision/scale.',
      'columns': none,
      'decimal_option': none,
      'warnings': []
    }) }}
  {% endif %}

  {% set folded = namespace(columns=[]) %}
  {% for col in ns.decimals %}
    {% if _federation_fits_bignumeric(col.precision, col.scale) %}
      {% set folded.columns = folded.columns + [_federation_copy_column(col, 'passthrough', 'NUMERIC', none, 'exact')] %}
    {% else %}
      {% set folded.columns = folded.columns + [_federation_copy_column(col, 'remote_cast', 'STRING', 'text', 'representation_change')] %}
    {% endif %}
  {% endfor %}
  {{ return({
    'ok': true,
    'error': none,
    'columns': ns.others + folded.columns,
    'decimal_option': none,
    'warnings': ['One or more decimal columns cannot be proven to fit BIGNUMERIC; those columns are remote-cast to text and pushdown is lost.']
  }) }}
{% endmacro %}

{% macro _federation_restore_column_order(original_names, folded_columns) %}
  {% set ordered = namespace(columns=[]) %}
  {% for name in original_names %}
    {% for col in folded_columns %}
      {% if col.name == name %}
        {% set ordered.columns = ordered.columns + [col] %}
      {% endif %}
    {% endfor %}
  {% endfor %}
  {{ return(ordered.columns) }}
{% endmacro %}

{% macro _federation_build_remote_sql(provider, schema, table, columns) %}
  {% set relation = _federation_provider_render_remote_relation(provider, schema, table) %}
  {% set ns = namespace(needs_projection=false, select_list=[]) %}
  {% for col in columns %}
    {% if col.action == 'remote_cast' %}
      {% set ns.needs_projection = true %}
    {% endif %}
  {% endfor %}
  {% if not ns.needs_projection %}
    {{ return({'body': 'passthrough', 'pushdown': 'kept', 'remote_sql': 'select * from ' ~ relation}) }}
  {% endif %}
  {% for col in columns %}
    {% set quoted_name = _federation_quote_identifier(provider, col.name) %}
    {% if col.action == 'remote_cast' %}
      {% set remote_type = col.remote_type if col.remote_type else 'text' %}
      {% set expr = _federation_provider_render_remote_cast(provider, quoted_name, remote_type) %}
      {% set ns.select_list = ns.select_list + [expr ~ ' as ' ~ quoted_name] %}
    {% else %}
      {% set ns.select_list = ns.select_list + [quoted_name] %}
    {% endif %}
  {% endfor %}
  {{ return({
    'body': 'projection',
    'pushdown': 'lost',
    'remote_sql': 'select ' ~ (ns.select_list | join(', ')) ~ ' from ' ~ relation
  }) }}
{% endmacro %}

{% macro _federation_try_plan(connection, table, schema=None, type_policy=None, overrides=None, columns=None) %}
  {% if columns is none %}
    {% set loaded = _federation_try_load_pin(connection, table, schema) %}
    {% if not loaded.ok %}
      {{ return({'ok': false, 'error': loaded.error, 'plan': none}) }}
    {% endif %}
    {% set pin_columns = loaded.pin.columns %}
    {% set conn = loaded.connection %}
    {% set relation_schema = loaded.pin.schema %}
    {% set relation_table = loaded.pin.table %}
  {% else %}
    {% set resolved = _federation_try_resolve_connection(connection) %}
    {% if not resolved.ok %}
      {{ return({'ok': false, 'error': resolved.error, 'plan': none}) }}
    {% endif %}
    {% set conn = resolved.connection %}
    {% set relation_schema = schema if schema is not none else conn.default_schema %}
    {% if relation_schema is none %}
      {{ return({'ok': false, 'error': 'schema is required when passing explicit columns', 'plan': none}) }}
    {% endif %}
    {% set pin_columns = columns %}
    {% set relation_table = table %}
  {% endif %}

  {% set policy_result = _federation_resolve_policy(conn, type_policy) %}
  {% if not policy_result.ok %}
    {{ return({'ok': false, 'error': policy_result.error, 'plan': none}) }}
  {% endif %}
  {% set policy = policy_result.policy %}
  {% set type_overrides = _federation_package_type_overrides() %}
  {% set invocation_overrides = overrides if overrides is mapping else {} %}

  {% set classified_ns = namespace(columns=[]) %}
  {% for column in pin_columns %}
    {% set item = _federation_classify_column(conn.provider, column, policy, type_overrides, invocation_overrides) %}
    {% if not item.ok %}
      {{ return({'ok': false, 'error': item.error, 'plan': none}) }}
    {% endif %}
    {% set classified_ns.columns = classified_ns.columns + [item.classified] %}
  {% endfor %}

  {% set folded = _federation_fold_decimals(classified_ns.columns, policy) %}
  {% if not folded.ok %}
    {{ return({'ok': false, 'error': folded.error, 'plan': none}) }}
  {% endif %}

  {% set names = namespace(values=[]) %}
  {% for col in classified_ns.columns %}
    {% set names.values = names.values + [col.name] %}
  {% endfor %}
  {% set ordered_columns = _federation_restore_column_order(names.values, folded.columns) %}
  {% set sql_plan = _federation_build_remote_sql(conn.provider, relation_schema, relation_table, ordered_columns) %}

  {{ return({
    'ok': true,
    'error': none,
    'plan': {
      'provider': conn.provider,
      'connection': conn.alias,
      'connection_id': conn.connection_id,
      'schema': relation_schema,
      'table': relation_table,
      'policy': policy,
      'body': sql_plan.body,
      'decimal_option': folded.decimal_option,
      'pushdown': sql_plan.pushdown,
      'remote_sql': sql_plan.remote_sql,
      'warnings': folded.warnings,
      'columns': ordered_columns
    }
  }) }}
{% endmacro %}
