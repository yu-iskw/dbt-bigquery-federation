{# Metadata wrapper and provider-profile smoke tests. #}
{% macro test_postgres_metadata_remote_sql() %}
  {% set sql = dbt_bigquery_federation._federation_provider_metadata_remote_sql('cloud_sql_postgres', 'public', 'orders') %}
  {% set expected =
    'select column_name, data_type, udt_name, ordinal_position, is_nullable, ' ~
    'numeric_precision, numeric_scale, character_maximum_length ' ~
    'from information_schema.columns ' ~
    "where table_schema = 'public' and table_name = 'orders' " ~
    'order by ordinal_position'
  %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(sql),
    expected
  ) %}
{% endmacro %}

{% macro test_alloydb_metadata_uses_postgres_profile() %}
  {% set cloud_sql = dbt_bigquery_federation._federation_provider_metadata_remote_sql('cloud_sql_postgres', 'public', 'orders') %}
  {% set alloydb = dbt_bigquery_federation._federation_provider_metadata_remote_sql('alloydb_postgres', 'public', 'orders') %}
  {% do dbt_unittest.assert_equals(cloud_sql, alloydb) %}
{% endmacro %}

{% macro test_metadata_external_query_wrapper() %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection('application_pg') %}
  {% do dbt_unittest.assert_equals(resolved.ok, true) %}
  {% set sql = dbt_bigquery_federation._federation_metadata_query_sql(resolved.connection, 'public', 'orders') %}
  {% do dbt_unittest.assert_equals('EXTERNAL_QUERY' in sql, true) %}
  {% do dbt_unittest.assert_equals('information_schema.columns' in sql, true) %}
{% endmacro %}

{% macro test_spanner_metadata_uses_dedicated_connection() %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection('spanner_app') %}
  {% do dbt_unittest.assert_equals(resolved.ok, true) %}
  {% set sql = dbt_bigquery_federation._federation_metadata_query_sql(resolved.connection, '', 'Orders') %}
  {% do dbt_unittest.assert_equals('projects/example/locations/us/connections/spanner-metadata' in sql, true) %}
  {% do dbt_unittest.assert_equals('projects/example/locations/us/connections/spanner-data' in sql, false) %}
  {% do dbt_unittest.assert_equals('information_schema.columns' in sql, true) %}
{% endmacro %}
