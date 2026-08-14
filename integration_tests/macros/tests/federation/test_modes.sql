{% macro test_metadata_mode_auto_prefers_pin() %}
  {% set mode = dbt_bigquery_federation._federation_resolve_metadata_mode('application_pg', 'orders', 'public', 'auto') %}
  {% do dbt_unittest.assert_equals(mode.ok, true) %}
  {% do dbt_unittest.assert_equals(mode.mode, 'pinned') %}
{% endmacro %}

{% macro test_metadata_mode_live_is_explicit() %}
  {% set mode = dbt_bigquery_federation._federation_resolve_metadata_mode('application_pg', 'orders', 'public', 'live') %}
  {% do dbt_unittest.assert_equals(mode.ok, true) %}
  {% do dbt_unittest.assert_equals(mode.mode, 'live') %}
{% endmacro %}

{% macro test_metadata_mode_auto_uses_live_without_pin() %}
  {% set mode = dbt_bigquery_federation._federation_resolve_metadata_mode('application_pg', 'not_pinned', 'public', 'auto') %}
  {% do dbt_unittest.assert_equals(mode.ok, true) %}
  {% do dbt_unittest.assert_equals(mode.mode, 'live') %}
{% endmacro %}

{% macro test_live_parse_stub_is_passthrough() %}
  {% set stub = dbt_bigquery_federation._federation_parse_stub('application_pg', 'orders', 'public') %}
  {% do dbt_unittest.assert_equals(stub.ok, true) %}
  {% do dbt_unittest.assert_equals('EXTERNAL_QUERY' in stub.sql, true) %}
  {% do dbt_unittest.assert_equals('select * from' in stub.sql, true) %}
{% endmacro %}
