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
    dbt_bigquery_federation._federation_connection_id_is_valid('projects/example/locations/us/connections/application pg'),
    false
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_connection_id_is_valid('projects/example/locations/us/connections/application-pg /oops'),
    false
  ) %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection('missing_alias') %}
  {% do dbt_unittest.assert_equals(resolved.ok, false) %}
{% endmacro %}

{% macro test_provider_descriptors() %}
  {% set cloud_sql = dbt_bigquery_federation._federation_provider_descriptor('cloud_sql_postgres') %}
  {% set alloydb = dbt_bigquery_federation._federation_provider_descriptor('alloydb_postgres') %}
  {% set spanner = dbt_bigquery_federation._federation_provider_descriptor('spanner_google_sql') %}
  {% do dbt_unittest.assert_equals(cloud_sql.dialect, 'postgres') %}
  {% do dbt_unittest.assert_equals(alloydb.dialect, 'postgres') %}
  {% do dbt_unittest.assert_equals(cloud_sql.type_profile, 'postgres_federation') %}
  {% do dbt_unittest.assert_equals(alloydb.type_profile, 'postgres_federation') %}
  {% do dbt_unittest.assert_equals(cloud_sql.connection_kind, 'cloud_sql') %}
  {% do dbt_unittest.assert_equals(alloydb.connection_kind, 'alloydb') %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_capability('alloydb_postgres', 'schema_discovery'),
    true
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_is_supported('spanner_google_sql'),
    true
  ) %}
  {% do dbt_unittest.assert_equals(spanner.connection_kind, 'spanner') %}
  {% do dbt_unittest.assert_equals(spanner.type_profile, 'spanner_google_federation') %}
{% endmacro %}

{% macro test_alloydb_connection_resolution() %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection('analytics_alloydb') %}
  {% do dbt_unittest.assert_equals(resolved.ok, true) %}
  {% do dbt_unittest.assert_equals(resolved.connection.provider, 'alloydb_postgres') %}
  {% do dbt_unittest.assert_equals(resolved.connection.connection_kind, 'alloydb') %}
  {% do dbt_unittest.assert_equals(resolved.connection.dialect, 'postgres') %}
  {% do dbt_unittest.assert_equals(resolved.connection.metadata_profile, 'postgres_information_schema') %}
  {% do dbt_unittest.assert_equals(resolved.connection.type_profile, 'postgres_federation') %}
  {% do dbt_unittest.assert_equals(resolved.connection.metadata_connection_id, resolved.connection.connection_id) %}
{% endmacro %}

{% macro test_spanner_metadata_connection_resolution() %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection('spanner_app') %}
  {% do dbt_unittest.assert_equals(resolved.ok, true) %}
  {% do dbt_unittest.assert_equals(resolved.connection.provider, 'spanner_google_sql') %}
  {% do dbt_unittest.assert_equals(
    resolved.connection.connection_id,
    'projects/example/locations/us/connections/spanner-data'
  ) %}
  {% do dbt_unittest.assert_equals(
    resolved.connection.metadata_connection_id,
    'projects/example/locations/us/connections/spanner-metadata'
  ) %}
{% endmacro %}

{% macro test_connection_rejects_defaults_block() %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection('stale_defaults_pg') %}
  {% do dbt_unittest.assert_equals(resolved.ok, false) %}
  {% do dbt_unittest.assert_equals('must not set defaults' in resolved.error, true) %}
{% endmacro %}

{% macro test_schema_is_required_when_omitted() %}
  {% set stub = dbt_bigquery_federation._federation_parse_stub('application_pg', 'orders') %}
  {% do dbt_unittest.assert_equals(stub.ok, false) %}
  {% do dbt_unittest.assert_equals(stub.error, 'schema is required for application_pg.orders') %}
  {% set pin = dbt_bigquery_federation._federation_try_load_pin('application_pg', 'orders') %}
  {% do dbt_unittest.assert_equals(pin.ok, false) %}
  {% do dbt_unittest.assert_equals(pin.error, 'schema is required for application_pg.orders') %}
{% endmacro %}
