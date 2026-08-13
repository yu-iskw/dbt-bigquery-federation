{% macro test_federated_relation_renders_passthrough() %}
  {% set sql = dbt_bigquery_federation.federated_relation('application_pg', 'orders', 'public') %}
  {% set actual = dbt_bigquery_federation._federation_collapse_ws(sql) %}
  {% set expected = "EXTERNAL_QUERY('projects/example/locations/us/connections/application-pg', '''select * from public.orders''')" %}
  {% do dbt_unittest.assert_equals(actual, expected) %}

  {% set projected = dbt_bigquery_federation.federated_relation('application_pg', 'users', 'public') %}
  {% set projected_actual = dbt_bigquery_federation._federation_collapse_ws(projected) %}
  {% set projected_expected = "EXTERNAL_QUERY('projects/example/locations/us/connections/application-pg', '''select id, cast(user_uuid as text) as user_uuid, cast(payload as text) as payload from public.users''')" %}
  {% do dbt_unittest.assert_equals(projected_actual, projected_expected) %}
{% endmacro %}
