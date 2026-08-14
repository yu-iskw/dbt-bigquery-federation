{% macro test_external_query_renders_without_planning() %}
  {% set sql = dbt_bigquery_federation.external_query(
    'application_pg',
    'select id, created_at from public.orders'
  ) %}
  {% set actual = dbt_bigquery_federation._federation_collapse_ws(sql) %}
  {% set expected = "EXTERNAL_QUERY('projects/example/locations/us/connections/application-pg', 'select id, created_at from public.orders')" %}
  {% do dbt_unittest.assert_equals(actual, expected) %}

  {% set quoted = dbt_bigquery_federation.external_query(
    'application_pg',
    "select * from t where status = 'open'"
  ) %}
  {% set quoted_actual = dbt_bigquery_federation._federation_collapse_ws(quoted) %}
  {% set quoted_expected = "EXTERNAL_QUERY('projects/example/locations/us/connections/application-pg', 'select * from t where status = \\'open\\'')" %}
  {% do dbt_unittest.assert_equals(quoted_actual, quoted_expected) %}

  {% set multiline = dbt_bigquery_federation.external_query(
    'application_pg',
    'select 1\nfrom t'
  ) %}
  {% set multiline_actual = dbt_bigquery_federation._federation_collapse_ws(multiline) %}
  {% set multiline_expected = "EXTERNAL_QUERY('projects/example/locations/us/connections/application-pg', 'select 1\\nfrom t')" %}
  {% do dbt_unittest.assert_equals(multiline_actual, multiline_expected) %}

  {% set spanner = dbt_bigquery_federation.external_query(
    'spanner_app',
    'select * from `Orders`'
  ) %}
  {% set spanner_actual = dbt_bigquery_federation._federation_collapse_ws(spanner) %}
  {% set spanner_expected = "EXTERNAL_QUERY('projects/example/locations/us/connections/spanner-data', 'select * from `Orders`', '" ~ '{"query_execution_priority":"low"}' ~ "')" %}
  {% do dbt_unittest.assert_equals(spanner_actual, spanner_expected) %}
{% endmacro %}
