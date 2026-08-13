{% macro test_quote_safe_and_mixed_case_identifiers() %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._cloud_sql_postgres_quote_identifier('orders'),
    'orders'
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._cloud_sql_postgres_quote_identifier('Orders'),
    '"Orders"'
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._cloud_sql_postgres_quote_identifier('order-id'),
    '"order-id"'
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._cloud_sql_postgres_quote_identifier('weird"name'),
    '"weird""name"'
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_identifier_is_safe_unquoted('public'),
    true
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_identifier_is_safe_unquoted('Public'),
    false
  ) %}
{% endmacro %}
