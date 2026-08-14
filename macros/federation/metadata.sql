{% macro get_remote_columns(connection, table, schema=None) -%}
  {{ return(adapter.dispatch('get_remote_columns', 'dbt_bigquery_federation')(connection, table, schema)) }}
{%- endmacro %}

{% macro default__get_remote_columns(connection, table, schema=None) -%}
  {% set result = dbt_bigquery_federation._federation_try_get_remote_columns(connection, table, schema) %}
  {% if not result.ok %}
    {{ exceptions.raise_compiler_error(result.error) }}
  {% endif %}
  {{ return(result.columns) }}
{%- endmacro %}

{% macro _federation_provider_metadata_remote_sql(provider, schema, table) %}
  {% set descriptor = dbt_bigquery_federation._federation_provider_descriptor(provider) %}
  {% if descriptor is none %}
    {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
  {% endif %}
  {% if descriptor.metadata_profile == 'postgres_information_schema' %}
    {% set schema_lit = dbt_bigquery_federation._federation_provider_quote_literal(provider, schema) %}
    {% set table_lit = dbt_bigquery_federation._federation_provider_quote_literal(provider, table) %}
    {{ return(
      'select column_name, data_type, udt_name, ordinal_position, is_nullable, ' ~
      'numeric_precision, numeric_scale, character_maximum_length ' ~
      'from information_schema.columns ' ~
      'where table_schema = ' ~ schema_lit ~ ' and table_name = ' ~ table_lit ~ ' ' ~
      'order by ordinal_position'
    ) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation metadata profile: ' ~ descriptor.metadata_profile) }}
{% endmacro %}

{% macro _federation_metadata_query_sql(connection_cfg, schema, table) %}
  {% set remote_sql = dbt_bigquery_federation._federation_provider_metadata_remote_sql(connection_cfg.provider, schema, table) %}
  {% set external = dbt_bigquery_federation._render_external_query(connection_cfg.connection_id, remote_sql, none) %}
  {{ return('select * from ' ~ external) }}
{% endmacro %}

{% macro _federation_normalize_metadata_result(provider, result) %}
  {% if result is none %}
    {{ return({'ok': false, 'error': 'Metadata query returned no result object', 'columns': none}) }}
  {% endif %}
  {% set names = result.columns['column_name'].values() %}
  {% set data_types = result.columns['data_type'].values() %}
  {% set udt_names = result.columns['udt_name'].values() %}
  {% set ordinals = result.columns['ordinal_position'].values() %}
  {% set nullables = result.columns['is_nullable'].values() %}
  {% set precisions = result.columns['numeric_precision'].values() %}
  {% set scales = result.columns['numeric_scale'].values() %}
  {% set lengths = result.columns['character_maximum_length'].values() %}
  {% set normalized = namespace(columns=[]) %}
  {% for i in range(names | length) %}
    {% set raw_type = data_types[i] %}
    {% set source_type = dbt_bigquery_federation._federation_provider_normalize_type_name(provider, raw_type) %}
    {% do normalized.columns.append({
      'name': names[i] | string,
      'data_type': source_type,
      'raw_data_type': raw_type | string,
      'udt_name': udt_names[i] if udt_names[i] is not none else none,
      'ordinal_position': ordinals[i] | int,
      'nullable': (nullables[i] | string | upper) == 'YES',
      'precision': precisions[i] | int if precisions[i] is not none else none,
      'scale': scales[i] | int if scales[i] is not none else none,
      'character_maximum_length': lengths[i] | int if lengths[i] is not none else none
    }) %}
  {% endfor %}
  {{ return({'ok': true, 'error': none, 'columns': normalized.columns}) }}
{% endmacro %}

{% macro _federation_try_get_remote_columns(connection, table, schema=None) %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection(connection) %}
  {% if not resolved.ok %}
    {{ return({'ok': false, 'error': resolved.error, 'columns': none, 'connection': none, 'schema': none, 'table': table}) }}
  {% endif %}
  {% set conn = resolved.connection %}
  {% if not dbt_bigquery_federation._federation_provider_capability(conn.provider, 'schema_discovery', false) %}
    {{ return({'ok': false, 'error': 'Provider ' ~ conn.provider ~ ' does not support schema discovery', 'columns': none, 'connection': conn, 'schema': schema, 'table': table}) }}
  {% endif %}
  {% set relation_schema = schema if schema is not none else conn.default_schema %}
  {% if relation_schema is none %}
    {{ return({'ok': false, 'error': 'schema is required for ' ~ connection ~ '.' ~ table ~ ' (no connection defaults.schema)', 'columns': none, 'connection': conn, 'schema': none, 'table': table}) }}
  {% endif %}
  {% if not execute %}
    {{ return({'ok': false, 'error': 'Live metadata discovery requires execute=true; use pinned metadata during parse-only evaluation', 'columns': none, 'connection': conn, 'schema': relation_schema, 'table': table}) }}
  {% endif %}
  {% set query_sql = dbt_bigquery_federation._federation_metadata_query_sql(conn, relation_schema, table) %}
  {% set query_result = run_query(query_sql) %}
  {% set normalized = dbt_bigquery_federation._federation_normalize_metadata_result(conn.provider, query_result) %}
  {% if not normalized.ok %}
    {{ return({'ok': false, 'error': normalized.error, 'columns': none, 'connection': conn, 'schema': relation_schema, 'table': table}) }}
  {% endif %}
  {% if normalized.columns | length == 0 %}
    {{ return({'ok': false, 'error': 'No remote columns found for ' ~ conn.provider ~ ' ' ~ relation_schema ~ '.' ~ table, 'columns': [], 'connection': conn, 'schema': relation_schema, 'table': table}) }}
  {% endif %}
  {{ return({'ok': true, 'error': none, 'columns': normalized.columns, 'connection': conn, 'schema': relation_schema, 'table': table, 'query_sql': query_sql}) }}
{% endmacro %}
