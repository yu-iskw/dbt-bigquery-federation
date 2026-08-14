{% macro test_connection_id_validation() %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_connection_id_is_valid('projects/example/locations/us/connections/application-pg'),
    true
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_connection_id_is_valid('application-pg'),
    false
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_connection_id_is_valid(none),
    false
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_connection_id_is_valid('projects/example/locations/us/connections/application-pg\n'),
    true
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_connection_id_is_valid('projects/example/locations/us/connections/application-pg /oops'),
    false
  ) %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection('missing_alias') %}
  {% do dbt_unittest.assert_equals(resolved.ok, false) %}
{% endmacro %}
