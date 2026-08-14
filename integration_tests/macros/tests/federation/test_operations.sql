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

{% macro test_schema_diff_no_changes() %}
  {% set columns = [
    {'name': 'id', 'data_type': 'bigint', 'precision': none, 'scale': none},
    {'name': 'amount', 'data_type': 'numeric', 'precision': 12, 'scale': 2}
  ] %}
  {% set diff = dbt_bigquery_federation._federation_schema_diff_columns(columns, columns) %}
  {% do dbt_unittest.assert_equals(diff.has_changes, false) %}
{% endmacro %}
