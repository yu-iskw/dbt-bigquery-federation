{# RFC §12: an allowlisted remote_type is the only consumer token concatenated into
   remote SQL. Identifiers and literals go through the provider quoter; connection
   IDs are validated before they reach the renderer. quote_literal is on the RFC
   surface so hatch SQL can quote values, but the planner never concatenates
   literals into remote SQL. #}

{% macro test_quote_safe_and_mixed_case_identifiers() %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_quote_identifier('cloud_sql_postgres', 'orders'),
    '"orders"'
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_quote_identifier('cloud_sql_postgres', 'user'),
    '"user"'
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_quote_identifier('cloud_sql_postgres', 'Orders'),
    '"Orders"'
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_quote_identifier('cloud_sql_postgres', 'order-id'),
    '"order-id"'
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_quote_identifier('cloud_sql_postgres', 'weird"name'),
    '"weird""name"'
  ) %}
{% endmacro %}

{% macro test_quote_literal_doubles_single_quotes() %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_quote_literal('cloud_sql_postgres', "it's"),
    "'it''s'"
  ) %}
{% endmacro %}

{% macro test_spanner_quote_literal_uses_googlesql_escapes() %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_quote_literal('spanner_google_sql', "it's"),
    "'" ~ 'it' ~ "\\'" ~ 's' ~ "'"
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_quote_literal('spanner_google_sql', 'a\\b'),
    "'" ~ 'a\\\\b' ~ "'"
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_quote_literal('spanner_google_sql', "x\\' OR 1=1 --"),
    "'" ~ 'x\\\\' ~ "\\'" ~ ' OR 1=1 --' ~ "'"
  ) %}
{% endmacro %}
