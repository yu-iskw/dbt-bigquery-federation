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

{% macro _test_spanner_google_expected_scalar_matrix() %}
  {% set matrix = {
    'BOOL': {'kind': 'native', 'target': 'BOOL', 'lossiness': 'exact', 'remote_type': 'STRING'},
    'BYTES': {'kind': 'native', 'target': 'BYTES', 'lossiness': 'exact', 'remote_type': 'STRING'},
    'DATE': {'kind': 'native', 'target': 'DATE', 'lossiness': 'exact', 'remote_type': 'STRING'},
    'FLOAT64': {'kind': 'native', 'target': 'FLOAT64', 'lossiness': 'exact', 'remote_type': 'STRING'},
    'INT64': {'kind': 'native', 'target': 'INT64', 'lossiness': 'exact', 'remote_type': 'STRING'},
    'JSON': {'kind': 'native', 'target': 'JSON', 'lossiness': 'exact', 'remote_type': 'STRING'},
    'NUMERIC': {'kind': 'native', 'target': 'NUMERIC', 'lossiness': 'range_risk', 'remote_type': 'STRING'},
    'STRING': {'kind': 'native', 'target': 'STRING', 'lossiness': 'exact', 'remote_type': 'STRING'},
    'TIMESTAMP': {'kind': 'native', 'target': 'TIMESTAMP', 'lossiness': 'precision_loss', 'remote_type': 'STRING'}
  } %}
  {{ return(matrix) }}
{% endmacro %}

{% macro test_spanner_google_type_mapping() %}
  {% set expected = _test_spanner_google_expected_scalar_matrix() %}
  {% for data_type, want in expected.items() %}
    {% set entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', data_type) %}
    {% do dbt_unittest.assert_equals(entry.kind, want.kind) %}
    {% do dbt_unittest.assert_equals(entry.target, want.target) %}
    {% do dbt_unittest.assert_equals(entry.lossiness, want.lossiness) %}
    {% do dbt_unittest.assert_equals(entry.remote_type, want.remote_type) %}
    {% do dbt_unittest.assert_equals(entry.data_type, data_type) %}
  {% endfor %}

  {% set array_entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'ARRAY<STRING(64)>') %}
  {% do dbt_unittest.assert_equals(array_entry.kind, 'native') %}
  {% do dbt_unittest.assert_equals(array_entry.target, 'ARRAY') %}
  {% do dbt_unittest.assert_equals(array_entry.lossiness, 'exact') %}
  {% do dbt_unittest.assert_equals(array_entry.remote_type, 'STRING') %}
  {% do dbt_unittest.assert_equals(array_entry.data_type, 'ARRAY<STRING>') %}

  {% set array_int_entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'ARRAY<INT64>') %}
  {% do dbt_unittest.assert_equals(array_int_entry.kind, 'native') %}
  {% do dbt_unittest.assert_equals(array_int_entry.target, 'ARRAY') %}

  {% set struct_entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'STRUCT<id INT64>') %}
  {% do dbt_unittest.assert_equals(struct_entry.kind, 'unsupported') %}
  {% do dbt_unittest.assert_equals(struct_entry.target, none) %}
  {% do dbt_unittest.assert_equals(struct_entry.remote_type, none) %}
  {% set bare_struct = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'STRUCT') %}
  {% do dbt_unittest.assert_equals(bare_struct.kind, 'unsupported') %}
  {% do dbt_unittest.assert_equals(bare_struct.remote_type, none) %}
  {% set array_struct_entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'ARRAY<STRUCT<id INT64>>') %}
  {% do dbt_unittest.assert_equals(array_struct_entry.kind, 'unsupported') %}
  {% do dbt_unittest.assert_equals(array_struct_entry.remote_type, none) %}

  {% set unknown = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', 'GEOGRAPHY') %}
  {% do dbt_unittest.assert_equals(unknown.kind, 'unknown') %}
  {% do dbt_unittest.assert_equals(unknown.target, none) %}
  {% do dbt_unittest.assert_equals(unknown.lossiness, 'unknown') %}
  {% do dbt_unittest.assert_equals(unknown.remote_type, none) %}
{% endmacro %}

{% macro test_spanner_google_type_length_modifiers_to_bigquery_target() %}
  {# Length modifiers normalize then map to the same BigQuery target as the scalar. #}
  {% set cases = [
    ['STRING(MAX)', 'STRING', 'STRING'],
    ['STRING(64)', 'STRING', 'STRING'],
    ['string(64)', 'STRING', 'STRING'],
    ['BYTES(1024)', 'BYTES', 'BYTES'],
    ['bytes(8)', 'BYTES', 'BYTES'],
    ['ARRAY<STRING(16)>', 'ARRAY<STRING>', 'ARRAY'],
    ['ARRAY<BYTES(MAX)>', 'ARRAY<BYTES>', 'ARRAY']
  ] %}
  {% for case in cases %}
    {% set entry = dbt_bigquery_federation._federation_provider_type_entry('spanner_google_sql', case[0]) %}
    {% do dbt_unittest.assert_equals(entry.kind, 'native') %}
    {% do dbt_unittest.assert_equals(entry.data_type, case[1]) %}
    {% do dbt_unittest.assert_equals(entry.target, case[2]) %}
  {% endfor %}
{% endmacro %}

{% macro test_spanner_google_render_remote_cast_smoke() %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_render_remote_cast('spanner_google_sql', '`Id`', 'STRING'),
    'CAST(`Id` AS STRING)'
  ) %}
{% endmacro %}

{% macro test_spanner_google_sql_rendering() %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_provider_render_remote_relation('spanner_google_sql', '', 'Orders'), '`Orders`') %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_provider_render_remote_relation('spanner_google_sql', 'sales', 'Orders'), '`sales`.`Orders`') %}
  {% set rendered = dbt_bigquery_federation._federation_render_external_query('projects/p/locations/us/connections/spanner', 'select * from `Orders`', none, 'low') %}
  {% set expected = "EXTERNAL_QUERY('projects/p/locations/us/connections/spanner', 'select * from `Orders`', '" ~ '{"query_execution_priority":"low"}' ~ "')" %}
  {% do dbt_unittest.assert_equals(rendered, expected) %}
{% endmacro %}

{% macro test_spanner_google_live_plan_native_types() %}
  {% do test_plan_from_ir_spanner_orders_native() %}
{% endmacro %}

{% macro test_spanner_google_struct_cannot_federate() %}
  {% do test_plan_from_ir_spanner_struct_still_fails() %}
  {% set conn = _ir_fixture_connection(
    'spanner_google_sql',
    'spanner_app',
    'projects/p/locations/us/connections/spanner'
  ) %}
  {% set array_struct_result = dbt_bigquery_federation._federation_try_plan_columns(
    conn, '', 'Orders', [{'name': 'payload', 'data_type': 'ARRAY<STRUCT<id INT64>>'}], none, none, 'live'
  ) %}
  {% do dbt_unittest.assert_equals(array_struct_result.ok, false) %}
  {% do dbt_unittest.assert_equals('ARRAY<STRUCT<id INT64>>' in array_struct_result.error, true) %}
{% endmacro %}

{% macro test_spanner_pinned_federated_relation_renders_priority() %}
  {% set sql = dbt_bigquery_federation.federated_relation('spanner_app', 'Orders', '') %}
  {% set actual = dbt_bigquery_federation._federation_collapse_ws(sql) %}
  {% set expected = "EXTERNAL_QUERY('projects/example/locations/us/connections/spanner-data', 'select `id`, `payload` from `Orders`', '" ~ '{"query_execution_priority":"low"}' ~ "')" %}
  {% do dbt_unittest.assert_equals(actual, expected) %}
{% endmacro %}
