{% macro test_external_query_renders_without_planning() %}
  {% set sql = dbt_bigquery_federation.external_query(
    'application_pg',
    'select id, created_at from public.orders'
  ) %}
  {% set actual = dbt_bigquery_federation._federation_collapse_ws(sql) %}
  {% set expected = "EXTERNAL_QUERY('projects/example/locations/us/connections/application-pg', '''select id, created_at from public.orders''')" %}
  {% do dbt_unittest.assert_equals(actual, expected) %}
{% endmacro %}
