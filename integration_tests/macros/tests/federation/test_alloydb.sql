{% macro test_alloydb_postgres_plan_uses_shared_profile() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('analytics_alloydb', 'orders', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.provider, 'alloydb_postgres') %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql), 'select "id", cast("user_uuid" as text) as "user_uuid", cast("payload" as text) as "payload" from "public"."orders"') %}
{% endmacro %}

{% macro test_alloydb_postgres_router_matches_postgres_dialect() %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_provider_quote_identifier('alloydb_postgres', 'Orders'), '"Orders"') %}
  {% set uuid_entry = dbt_bigquery_federation._federation_provider_type_entry('alloydb_postgres', 'uuid') %}
  {% do dbt_unittest.assert_equals(uuid_entry.kind, 'unsupported') %}
  {% do dbt_unittest.assert_equals(uuid_entry.remote_type, 'text') %}
{% endmacro %}

{% macro test_alloydb_postgres_live_plan_conformance() %}
  {% set conn = {'provider': 'alloydb_postgres', 'alias': 'alloydb', 'connection_id': 'projects/p/locations/us/connections/alloydb', 'policy': 'safe', 'query_execution_priority': none} %}
  {% set columns = [
    {'name': 'id', 'data_type': 'bigint'},
    {'name': 'user_uuid', 'data_type': 'uuid'},
    {'name': 'payload', 'data_type': 'jsonb'}
  ] %}
  {% set result = dbt_bigquery_federation._federation_try_plan_columns(conn, 'public', 'orders', columns) %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.provider, 'alloydb_postgres') %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql), 'select "id", cast("user_uuid" as text) as "user_uuid", cast("payload" as text) as "payload" from "public"."orders"') %}
{% endmacro %}
