{# Offline unit coverage for _federation_normalize_metadata_rows (no warehouse I/O). #}
{% macro test_normalize_metadata_rows_postgres() %}
  {% set rows = [
    {
      'column_name': 'id',
      'data_type': 'bigint',
      'udt_name': 'int8',
      'ordinal_position': 1,
      'is_nullable': 'NO',
      'numeric_precision': 64,
      'numeric_scale': 0,
      'character_maximum_length': none
    },
    {
      'column_name': 'col_numeric',
      'data_type': 'numeric',
      'udt_name': 'numeric',
      'ordinal_position': 2,
      'is_nullable': 'NO',
      'numeric_precision': 12,
      'numeric_scale': 2,
      'character_maximum_length': none
    },
    {
      'column_name': 'col_varchar',
      'data_type': 'character varying',
      'udt_name': 'varchar',
      'ordinal_position': 3,
      'is_nullable': 'YES',
      'numeric_precision': none,
      'numeric_scale': none,
      'character_maximum_length': 32
    },
    {
      'column_name': 'col_uuid',
      'data_type': 'uuid',
      'udt_name': 'uuid',
      'ordinal_position': 4,
      'is_nullable': 'NO',
      'numeric_precision': none,
      'numeric_scale': none,
      'character_maximum_length': none
    }
  ] %}
  {% set normalized = dbt_bigquery_federation._federation_normalize_metadata_rows('cloud_sql_postgres', rows) %}
  {% do dbt_unittest.assert_equals(normalized.ok, true) %}
  {% do dbt_unittest.assert_equals(normalized.columns | length, 4) %}
  {% do dbt_unittest.assert_equals(normalized.columns[0].name, 'id') %}
  {% do dbt_unittest.assert_equals(normalized.columns[0].data_type, 'bigint') %}
  {% do dbt_unittest.assert_equals(normalized.columns[0].nullable, false) %}
  {% do dbt_unittest.assert_equals(normalized.columns[0].precision, none) %}
  {% do dbt_unittest.assert_equals(normalized.columns[1].name, 'col_numeric') %}
  {% do dbt_unittest.assert_equals(normalized.columns[1].data_type, 'numeric') %}
  {% do dbt_unittest.assert_equals(normalized.columns[1].precision, 12) %}
  {% do dbt_unittest.assert_equals(normalized.columns[1].scale, 2) %}
  {% do dbt_unittest.assert_equals(normalized.columns[2].character_maximum_length, 32) %}
  {% do dbt_unittest.assert_equals(normalized.columns[2].nullable, true) %}
  {% do dbt_unittest.assert_equals(normalized.columns[3].data_type, 'uuid') %}
  {% do dbt_unittest.assert_equals(normalized.columns[3].udt_name, 'uuid') %}
{% endmacro %}

{% macro test_normalize_metadata_rows_spanner() %}
  {% set rows = [
    {
      'column_name': 'Id',
      'spanner_type': 'INT64',
      'ordinal_position': 1,
      'is_nullable': 'NO'
    },
    {
      'column_name': 'ColString',
      'spanner_type': 'STRING(64)',
      'ordinal_position': 2,
      'is_nullable': 'YES'
    },
    {
      'column_name': 'ColArray',
      'spanner_type': 'ARRAY<STRING(16)>',
      'ordinal_position': 3,
      'is_nullable': 'YES'
    }
  ] %}
  {% set normalized = dbt_bigquery_federation._federation_normalize_metadata_rows('spanner_google_sql', rows) %}
  {% do dbt_unittest.assert_equals(normalized.ok, true) %}
  {% do dbt_unittest.assert_equals(normalized.columns | length, 3) %}
  {% do dbt_unittest.assert_equals(normalized.columns[0].name, 'Id') %}
  {% do dbt_unittest.assert_equals(normalized.columns[0].data_type, 'INT64') %}
  {% do dbt_unittest.assert_equals(normalized.columns[0].nullable, false) %}
  {% do dbt_unittest.assert_equals(normalized.columns[1].data_type, 'STRING') %}
  {% do dbt_unittest.assert_equals(normalized.columns[1].raw_data_type, 'STRING(64)') %}
  {% do dbt_unittest.assert_equals(normalized.columns[1].nullable, true) %}
  {% do dbt_unittest.assert_equals(normalized.columns[2].data_type, 'ARRAY<STRING>') %}
  {% do dbt_unittest.assert_equals(normalized.columns[2].raw_data_type, 'ARRAY<STRING(16)>') %}
{% endmacro %}
