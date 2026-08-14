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
  {{ return(dbt_bigquery_federation._federation_numeric_fits(precision, scale, 38, 9, 29)) }}
{% endmacro %}

{% macro _federation_fits_bignumeric(precision, scale) %}
  {{ return(dbt_bigquery_federation._federation_numeric_fits(precision, scale, 76, 38, 38)) }}
{% endmacro %}

{% macro _federation_decimal_tier(precision, scale) %}
  {% if dbt_bigquery_federation._federation_fits_numeric(precision, scale) %}
    {{ return(0) }}
  {% endif %}
  {% if dbt_bigquery_federation._federation_fits_bignumeric(precision, scale) %}
    {{ return(1) }}
  {% endif %}
  {{ return(2) }}
{% endmacro %}

{% macro _federation_classified_column(column, source_type, action, target_type, remote_type, lossiness) %}
  {{ return({
    'name': column.get('name'),
    'source_type': source_type,
    'raw_data_type': column.get('raw_data_type', column.get('data_type')),
    'precision': column.get('precision'),
    'scale': column.get('scale'),
    'action': action,
    'target_type': target_type,
    'remote_type': remote_type,
    'lossiness': lossiness
  }) }}
{% endmacro %}

{% macro _federation_lookup_override(column, type_overrides, invocation_overrides, source_type) %}
  {% set col_name = column.get('name') | string %}
  {% if col_name in invocation_overrides %}
    {{ return(invocation_overrides[col_name]) }}
  {% endif %}
  {% if column.get('strategy') %}
    {{ return({
      'strategy': column.get('strategy'),
      'remote_type': column.get('remote_type', 'text'),
      'target_type': column.get('target_type', 'STRING')
    }) }}
  {% endif %}
  {% if source_type in type_overrides %}
    {{ return(type_overrides[source_type]) }}
  {% endif %}
  {{ return(none) }}
{% endmacro %}

{% macro _federation_validate_remote_type(remote_type) %}
  {% set matched = modules.re.match('^[a-z_][a-z0-9_ ]*$', remote_type | string | lower | trim) %}
  {{ return(matched is not none) }}
{% endmacro %}

{% macro _federation_column_declared_type(column) %}
  {% set data_type = column.get('data_type') %}
  {% set udt_name = column.get('udt_name') %}
  {% if udt_name is not none and (data_type | string | lower | trim) == 'user-defined' %}
    {{ return(udt_name) }}
  {% endif %}
  {{ return(data_type) }}
{% endmacro %}

{% macro _federation_classify_column(provider, column, policy, type_overrides, invocation_overrides) %}
  {% if column is not mapping %}
    {{ return({'ok': false, 'error': 'Each column must be a mapping', 'classified': none}) }}
  {% endif %}
  {% set name = column.get('name') %}
  {% if not name %}
    {{ return({'ok': false, 'error': 'Column is missing name', 'classified': none}) }}
  {% endif %}
  {% set data_type = dbt_bigquery_federation._federation_column_declared_type(column) %}
  {% if not data_type %}
    {{ return({'ok': false, 'error': 'Column ' ~ name ~ ' is missing data_type', 'classified': none}) }}
  {% endif %}
  {% set source_type = dbt_bigquery_federation._federation_provider_normalize_type_name(provider, data_type) %}
  {% if modules.re.match('^(numeric|decimal)\\s*\\(', source_type) is not none %}
    {{ return({
      'ok': false,
      'error': 'Column ' ~ name ~ ' data_type ' ~ (data_type | string) ~ ' embeds precision/scale. Use bare numeric plus precision and scale fields.',
      'classified': none
    }) }}
  {% endif %}
  {% set override = dbt_bigquery_federation._federation_lookup_override(column, type_overrides, invocation_overrides, source_type) %}
  {% if override is not none and override is not mapping %}
    {{ return({'ok': false, 'error': 'Override for column ' ~ name ~ ' must be a mapping', 'classified': none}) }}
  {% endif %}
  {% if override is mapping %}
    {% set strategy = override.get('strategy') | string | lower %}
    {% if strategy == 'remote_cast' %}
      {% set remote_type = override.get('remote_type', 'text') %}
      {% if not dbt_bigquery_federation._federation_validate_remote_type(remote_type) %}
        {{ return({'ok': false, 'error': 'Column ' ~ name ~ ' override remote_type is not a safe remote type name', 'classified': none}) }}
      {% endif %}
      {{ return({'ok': true, 'error': none, 'classified': dbt_bigquery_federation._federation_classified_column(
        column, source_type, 'remote_cast', override.get('target_type', 'STRING'), remote_type, 'representation_change'
      )}) }}
    {% elif strategy == 'passthrough' %}
      {{ return({'ok': true, 'error': none, 'classified': dbt_bigquery_federation._federation_classified_column(
        column, source_type, 'passthrough', override.get('target_type', 'STRING'), none, override.get('lossiness', 'exact')
      )}) }}
    {% elif strategy == 'fail' %}
      {{ return({'ok': false, 'error': 'Column ' ~ name ~ ' is blocked by an explicit fail override', 'classified': none}) }}
    {% else %}
      {{ return({'ok': false, 'error': 'Unknown override strategy ' ~ strategy ~ ' for column ' ~ name, 'classified': none}) }}
    {% endif %}
  {% endif %}

  {% set entry = dbt_bigquery_federation._federation_provider_type_entry(provider, data_type) %}
  {% if entry.kind == 'native' %}
    {{ return({'ok': true, 'error': none, 'classified': dbt_bigquery_federation._federation_classified_column(
      column, entry.data_type, 'passthrough', entry.target, none, entry.lossiness
    )}) }}
  {% elif entry.kind == 'decimal' %}
    {{ return({'ok': true, 'error': none, 'classified': dbt_bigquery_federation._federation_classified_column(
      column, entry.data_type, 'decimal', 'NUMERIC', none, 'exact'
    )}) }}
  {% elif entry.kind == 'unsupported' %}
    {% if not entry.remote_type %}
      {{ return({
        'ok': false,
        'error': 'Column ' ~ name ~ ' has unsupported type ' ~ (data_type | string) ~ ' that cannot be federated.',
        'classified': none
      }) }}
    {% endif %}
    {% if policy == 'strict' %}
      {{ return({
        'ok': false,
        'error': 'Column ' ~ name ~ ' has unsupported type ' ~ (data_type | string) ~ ' under ' ~ policy ~ ' policy. Add type_overrides or pin strategy.',
        'classified': none
      }) }}
    {% endif %}
    {{ return({'ok': true, 'error': none, 'classified': dbt_bigquery_federation._federation_classified_column(
      column, entry.data_type, 'remote_cast', entry.target, entry.remote_type, entry.lossiness
    )}) }}
  {% endif %}
  {{ return({
    'ok': false,
    'error': 'Column ' ~ name ~ ' has unknown type ' ~ (data_type | string) ~ ' under ' ~ policy ~ ' policy. Add type_overrides or pin strategy.',
    'classified': none
  }) }}
{% endmacro %}

{% macro _federation_fold_decimals(classified_columns, policy) %}
  {% set scan = namespace(max_tier=0, has_decimal=false, remaining_max=0, offenders=[]) %}
  {% for col in classified_columns %}
    {% if col.action == 'decimal' %}
      {% set scan.has_decimal = true %}
      {% set tier = dbt_bigquery_federation._federation_decimal_tier(col.precision, col.scale) %}
      {% if tier > scan.max_tier %}
        {% set scan.max_tier = tier %}
      {% endif %}
      {% if tier == 2 %}
        {% do scan.offenders.append(col.name) %}
      {% elif tier > scan.remaining_max %}
        {% set scan.remaining_max = tier %}
      {% endif %}
    {% endif %}
  {% endfor %}
  {% if not scan.has_decimal %}
    {{ return({'ok': true, 'error': none, 'columns': classified_columns, 'decimal_option': none, 'warnings': []}) }}
  {% endif %}

  {% if scan.max_tier == 2 and policy == 'strict' %}
    {{ return({
      'ok': false,
      'error': 'Decimal columns are unbounded or exceed BIGNUMERIC under strict policy: ' ~ (scan.offenders | join(', ')) ~ '. Add an override or tighten the pin precision/scale.',
      'columns': none,
      'decimal_option': none,
      'warnings': []
    }) }}
  {% endif %}

  {% set fold_cfg = namespace(native_target='NUMERIC', decimal_option=none, warnings=[]) %}
  {% if scan.max_tier == 1 %}
    {% set fold_cfg.native_target = 'BIGNUMERIC' %}
    {% set fold_cfg.decimal_option = 'bignumeric' %}
  {% elif scan.max_tier == 2 %}
    {% set fold_cfg.warnings = ['One or more decimal columns cannot be proven to fit BIGNUMERIC; those columns are remote-cast to text and pushdown is lost.'] %}
    {% if scan.remaining_max == 1 %}
      {% set fold_cfg.native_target = 'BIGNUMERIC' %}
      {% set fold_cfg.decimal_option = 'bignumeric' %}
    {% endif %}
  {% endif %}

  {% set folded = namespace(columns=[]) %}
  {% for col in classified_columns %}
    {% if col.action != 'decimal' %}
      {% do folded.columns.append(col) %}
    {% elif scan.max_tier < 2 or dbt_bigquery_federation._federation_decimal_tier(col.precision, col.scale) < 2 %}
      {% do folded.columns.append(dbt_bigquery_federation._federation_classified_column(col, col.source_type, 'passthrough', fold_cfg.native_target, none, 'exact')) %}
    {% else %}
      {% do folded.columns.append(dbt_bigquery_federation._federation_classified_column(col, col.source_type, 'remote_cast', 'STRING', 'text', 'representation_change')) %}
    {% endif %}
  {% endfor %}
  {{ return({
    'ok': true,
    'error': none,
    'columns': folded.columns,
    'decimal_option': fold_cfg.decimal_option,
    'warnings': fold_cfg.warnings
  }) }}
{% endmacro %}

{% macro _federation_build_remote_sql(provider, schema, table, columns, stable=false) %}
  {% set relation = dbt_bigquery_federation._federation_provider_render_remote_relation(provider, schema, table) %}
  {% set ns = namespace(needs_projection=stable) %}
  {% for col in columns %}
    {% if col.action == 'remote_cast' %}
      {% set ns.needs_projection = true %}
    {% endif %}
  {% endfor %}
  {% if not ns.needs_projection %}
    {{ return({'body': 'passthrough', 'pushdown': 'kept', 'remote_sql': 'select * from ' ~ relation}) }}
  {% endif %}
  {% set projected = namespace(select_list=[]) %}
  {% for col in columns %}
    {% set quoted_name = dbt_bigquery_federation._federation_provider_quote_identifier(provider, col.name) %}
    {% if col.action == 'remote_cast' %}
      {% set remote_type = col.remote_type if col.remote_type else 'text' %}
      {% set expr = dbt_bigquery_federation._federation_provider_render_remote_cast(provider, quoted_name, remote_type) %}
      {% do projected.select_list.append(expr ~ ' as ' ~ quoted_name) %}
    {% else %}
      {% do projected.select_list.append(quoted_name) %}
    {% endif %}
  {% endfor %}
  {{ return({
    'body': 'projection',
    'pushdown': 'lost',
    'remote_sql': 'select ' ~ (projected.select_list | join(', ')) ~ ' from ' ~ relation
  }) }}
{% endmacro %}

{% macro _federation_try_plan(connection, table, schema=None, type_policy=None, overrides=None) %}
  {% set loaded = dbt_bigquery_federation._federation_try_load_pin(connection, table, schema) %}
  {% if not loaded.ok %}
    {{ return({'ok': false, 'error': loaded.error, 'plan': none}) }}
  {% endif %}
  {{ return(dbt_bigquery_federation._federation_try_plan_columns(
    loaded.connection, loaded.pin.schema, loaded.pin.table, loaded.pin.columns, type_policy, overrides, 'pinned'
  )) }}
{% endmacro %}
