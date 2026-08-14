{% macro test_spanner_google_provider_descriptor() %}
  {% set descriptor = dbt_bigquery_federation._federation_provider_descriptor('spanner_google_sql') %}
  {% do dbt_unittest.assert_equals(descriptor.connection_kind, 'spanner') %}
  {% do dbt_unittest.assert_equals(descriptor.dialect, 'spanner_google_sql') %}
  {% do dbt_unittest.assert_equals(descriptor.metadata_profile, 'spanner_google_information_schema') %}
  {% do dbt_unittest.assert_equals(descriptor.type_profile, 'spanner_google_federation') %}
  {% do dbt_unittest.assert_equals(descriptor.capabilities.query_execution_priority, true) %}
  {% do dbt_unittest.assert_equals(descriptor.capabilities.arrays, true) %}
  {% do dbt_unittest.assert_equals(descriptor.capabilities.structs, false) %}
{% endmacro %}

{% macro test_spanner_google_metadata_query() %}
  {% set sql = dbt_bigquery_federation._federation_provider_metadata_remote_sql('spanner_google_sql', '', 'Orders') %}
  {% set normalized = dbt_bigquery_federation._federation_collapse_ws(sql) %}
  {% do dbt_unittest.assert_equals('spanner_type' in normalized, true) %}
  {% do dbt_unittest.assert_equals("table_catalog = ''" in normalized, true) %}
  {% do dbt_unittest.assert_equals("table_schema = ''" in normalized, true) %}
  {% do dbt_unittest.assert_equals("table_name = 'Orders'" in normalized, true) %}
{% endmacro %}

{% macro test_spanner_google_type_mapping() %}
  {% set json_entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'JSON') %}
  {% do dbt_unittest.assert_equals(json_entry.kind, 'native') %}
  {% do dbt_unittest.assert_equals(json_entry.target, 'JSON') %}
  {% set array_entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'ARRAY<STRING(64)>') %}
  {% do dbt_unittest.assert_equals(array_entry.kind, 'native') %}
  {% do dbt_unittest.assert_equals(array_entry.target, 'ARRAY') %}
  {% set timestamp_entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'TIMESTAMP') %}
  {% do dbt_unittest.assert_equals(timestamp_entry.target, 'TIMESTAMP') %}
  {% do dbt_unittest.assert_equals(timestamp_entry.lossiness, 'precision_loss') %}
  {% set struct_entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'STRUCT<id INT64>') %}
  {% do dbt_unittest.assert_equals(struct_entry.kind, 'unsupported') %}
  {% do dbt_unittest.assert_equals(struct_entry.target, none) %}
  {% do dbt_unittest.assert_equals(struct_entry.remote_type, none) %}
  {% set array_struct_entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'ARRAY<STRUCT<id INT64>>') %}
  {% do dbt_unittest.assert_equals(array_struct_entry.kind, 'unsupported') %}
  {% do dbt_unittest.assert_equals(array_struct_entry.remote_type, none) %}
{% endmacro %}

{% macro test_spanner_google_sql_rendering() %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_provider_render_remote_relation('spanner_google_sql', '', 'Orders'), '`Orders`') %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_provider_render_remote_relation('spanner_google_sql', 'sales', 'Orders'), '`sales`.`Orders`') %}
  {% set rendered = dbt_bigquery_federation._federation_render_external_query('projects/p/locations/us/connections/spanner', 'select * from `Orders`', none, 'low') %}
  {% set expected = "EXTERNAL_QUERY('projects/p/locations/us/connections/spanner', 'select * from `Orders`', '" ~ '{"query_execution_priority":"low"}' ~ "')" %}
  {% do dbt_unittest.assert_equals(rendered, expected) %}
{% endmacro %}

{% macro test_spanner_google_live_plan_native_types() %}
  {% set conn = {'provider': 'spanner_google_sql', 'alias': 'spanner_app', 'connection_id': 'projects/p/locations/us/connections/spanner', 'policy': 'safe', 'query_execution_priority': 'low'} %}
  {% set columns = [{'name': 'id', 'data_type': 'INT64'}, {'name': 'payload', 'data_type': 'JSON'}, {'name': 'created_at', 'data_type': 'TIMESTAMP'}] %}
  {% set result = dbt_bigquery_federation._federation_try_plan_columns(conn, '', 'Orders', columns) %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'passthrough') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'kept') %}
  {% do dbt_unittest.assert_equals(result.plan.query_execution_priority, 'low') %}
  {% do dbt_unittest.assert_equals(result.plan.remote_sql, 'select * from `Orders`') %}
{% endmacro %}

{% macro test_spanner_google_struct_cannot_federate() %}
  {% set conn = {'provider': 'spanner_google_sql', 'alias': 'spanner_app', 'connection_id': 'projects/p/locations/us/connections/spanner', 'policy': 'safe'} %}
  {% set struct_result = dbt_bigquery_federation._federation_try_plan_columns(
    conn, '', 'Orders', [{'name': 'payload', 'data_type': 'STRUCT<id INT64>'}]
  ) %}
  {% do dbt_unittest.assert_equals(struct_result.ok, false) %}
  {% do dbt_unittest.assert_equals('unsupported type' in struct_result.error, true) %}
  {% do dbt_unittest.assert_equals('STRUCT<id INT64>' in struct_result.error, true) %}
  {% set array_struct_result = dbt_bigquery_federation._federation_try_plan_columns(
    conn, '', 'Orders', [{'name': 'payload', 'data_type': 'ARRAY<STRUCT<id INT64>>'}]
  ) %}
  {% do dbt_unittest.assert_equals(array_struct_result.ok, false) %}
  {% do dbt_unittest.assert_equals('ARRAY<STRUCT<id INT64>>' in array_struct_result.error, true) %}
{% endmacro %}

{% macro test_spanner_pinned_federated_relation_renders_priority() %}
  {% set sql = dbt_bigquery_federation.federated_relation('spanner_app', 'Orders') %}
  {% set actual = dbt_bigquery_federation._federation_collapse_ws(sql) %}
  {% set expected = "EXTERNAL_QUERY('projects/example/locations/us/connections/spanner-data', 'select * from `Orders`', '" ~ '{"query_execution_priority":"low"}' ~ "')" %}
  {% do dbt_unittest.assert_equals(actual, expected) %}
{% endmacro %}
