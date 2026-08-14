{% macro test_schema_diff_detects_add_remove_change() %}
  {% set pinned = [
    {'name': 'id', 'data_type': 'bigint', 'precision': none, 'scale': none},
    {'name': 'amount', 'data_type': 'numeric', 'precision': 12, 'scale': 2},
    {'name': 'legacy', 'data_type': 'text', 'precision': none, 'scale': none}
  ] %}
  {% set live = [
    {'name': 'id', 'data_type': 'bigint', 'precision': none, 'scale': none},
    {'name': 'amount', 'data_type': 'numeric', 'precision': 20, 'scale': 4},
    {'name': 'created_at', 'data_type': 'timestamp without time zone', 'precision': none, 'scale': none}
  ] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pinned, live) %}
  {% do dbt_unittest.assert_equals(diff.has_changes, true) %}
  {% do dbt_unittest.assert_equals(diff.added | length, 1) %}
  {% do dbt_unittest.assert_equals(diff.removed | length, 1) %}
  {% do dbt_unittest.assert_equals(diff.changed | length, 1) %}
  {% do dbt_unittest.assert_equals(diff.added[0].name, 'created_at') %}
  {% do dbt_unittest.assert_equals(diff.removed[0].name, 'legacy') %}
  {% do dbt_unittest.assert_equals(diff.changed[0].name, 'amount') %}
{% endmacro %}

{% macro test_schema_diff_user_defined_udt_matches_pin_type() %}
  {% set pinned = [{'name': 'user_uuid', 'data_type': 'uuid', 'precision': none, 'scale': none}] %}
  {% set live = [{'name': 'user_uuid', 'data_type': 'USER-DEFINED', 'udt_name': 'uuid', 'precision': none, 'scale': none}] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pinned, live) %}
  {% do dbt_unittest.assert_equals(diff.has_changes, false) %}
{% endmacro %}

{% macro test_schema_diff_no_changes() %}
  {% set columns = [
    {'name': 'id', 'data_type': 'bigint', 'precision': none, 'scale': none},
    {'name': 'amount', 'data_type': 'numeric', 'precision': 12, 'scale': 2}
  ] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(columns, columns) %}
  {% do dbt_unittest.assert_equals(diff.has_changes, false) %}
{% endmacro %}

{% macro test_schema_diff_report_includes_precision_scale() %}
  {% set pinned = [
    {'name': 'amount', 'data_type': 'numeric', 'precision': 12, 'scale': 2}
  ] %}
  {% set live = [
    {'name': 'amount', 'data_type': 'numeric', 'precision': 20, 'scale': 4}
  ] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pinned, live) %}
  {% set report = dbt_bigquery_federation._federation_format_schema_diff_report('public', 'orders', diff) %}
  {% do dbt_unittest.assert_equals('numeric(12,2) -> numeric(20,4)' in report, true) %}
  {% do dbt_unittest.assert_equals('~ amount ' in report, true) %}
{% endmacro %}

{% macro test_schema_diff_ignores_integer_information_schema_precision() %}
  {% set pinned = [{'name': 'id', 'data_type': 'bigint'}] %}
  {% set live = [{'name': 'id', 'data_type': 'bigint', 'precision': 64, 'scale': 0}] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pinned, live) %}
  {% do dbt_unittest.assert_equals(diff.has_changes, false) %}
{% endmacro %}

{% macro test_schema_diff_ignores_float_information_schema_precision() %}
  {% set pinned = [{'name': 'ratio', 'data_type': 'double precision'}] %}
  {% set live = [{'name': 'ratio', 'data_type': 'double precision', 'precision': 53, 'scale': none}] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pinned, live) %}
  {% do dbt_unittest.assert_equals(diff.has_changes, false) %}
{% endmacro %}

{% macro test_schema_diff_normalizes_timestamp_aliases() %}
  {% set pinned = [{'name': 'created_at', 'data_type': 'timestamp'}] %}
  {% set live = [{'name': 'created_at', 'data_type': 'timestamp without time zone'}] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pinned, live, 'cloud_sql_postgres') %}
  {% do dbt_unittest.assert_equals(diff.has_changes, false) %}
{% endmacro %}

{% macro test_schema_diff_normalizes_varchar_aliases() %}
  {% set pinned = [{'name': 'code', 'data_type': 'varchar', 'character_maximum_length': 20}] %}
  {% set live = [{'name': 'code', 'data_type': 'character varying', 'character_maximum_length': 20}] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pinned, live, 'cloud_sql_postgres') %}
  {% do dbt_unittest.assert_equals(diff.has_changes, false) %}
{% endmacro %}

{% macro test_schema_diff_detects_character_maximum_length_change() %}
  {% set pinned = [{'name': 'code', 'data_type': 'character varying', 'character_maximum_length': 20}] %}
  {% set live = [{'name': 'code', 'data_type': 'character varying', 'character_maximum_length': 255}] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pinned, live) %}
  {% do dbt_unittest.assert_equals(diff.has_changes, true) %}
  {% do dbt_unittest.assert_equals(diff.changed | length, 1) %}
  {% do dbt_unittest.assert_equals(diff.changed[0].name, 'code') %}
  {% set report = dbt_bigquery_federation._federation_format_schema_diff_report('public', 'orders', diff) %}
  {% do dbt_unittest.assert_equals('character varying(20) -> character varying(255)' in report, true) %}
{% endmacro %}

{% macro test_schema_diff_report_omits_integer_precision() %}
  {% set pinned = [{'name': 'id', 'data_type': 'bigint'}] %}
  {% set live = [{'name': 'id', 'data_type': 'integer', 'precision': 32, 'scale': 0}] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(pinned, live) %}
  {% set report = dbt_bigquery_federation._federation_format_schema_diff_report('public', 'orders', diff) %}
  {% do dbt_unittest.assert_equals('bigint -> integer' in report, true) %}
  {% do dbt_unittest.assert_equals('integer(32,0)' in report, false) %}
{% endmacro %}

{% macro test_yaml_double_quoted_escapes_special_characters() %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_yaml_double_quoted('id'), '"id"') %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_yaml_double_quoted('a: b'), '"a: b"') %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_yaml_double_quoted('x"y'), '"x\\"y"') %}
{% endmacro %}
