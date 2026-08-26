{# Layer-2 planner tests driven by normalized column IR fixtures (no live discovery). #}

{% macro test_plan_from_ir_postgres_type_matrix() %}
  {% set fixture = ir_fixture_postgres_type_matrix() %}
  {% set result = _ir_fixture_plan(fixture) %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, fixture.expected.body) %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, fixture.expected.pushdown) %}
  {% do dbt_unittest.assert_equals(result.plan.provider, 'cloud_sql_postgres') %}
  {% for col_name in fixture.expected.passthrough %}
    {% do _ir_fixture_assert_column_action(result.plan, col_name, 'passthrough') %}
  {% endfor %}
  {% for col_name in fixture.expected.remote_cast %}
    {% do _ir_fixture_assert_column_action(result.plan, col_name, 'remote_cast') %}
  {% endfor %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    fixture.expected.remote_sql
  ) %}
{% endmacro %}

{% macro test_plan_from_ir_alloydb_type_matrix_matches_postgres() %}
  {% set pg = ir_fixture_postgres_type_matrix() %}
  {% set alloydb = ir_fixture_alloydb_type_matrix() %}
  {% set pg_result = _ir_fixture_plan(pg) %}
  {% set alloydb_result = _ir_fixture_plan(alloydb) %}
  {% do dbt_unittest.assert_equals(pg_result.ok, true) %}
  {% do dbt_unittest.assert_equals(alloydb_result.ok, true) %}
  {% do dbt_unittest.assert_equals(alloydb_result.plan.provider, 'alloydb_postgres') %}
  {% do dbt_unittest.assert_equals(alloydb_result.plan.body, pg_result.plan.body) %}
  {% do dbt_unittest.assert_equals(alloydb_result.plan.pushdown, pg_result.plan.pushdown) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(alloydb_result.plan.remote_sql),
    dbt_bigquery_federation._federation_collapse_ws(pg_result.plan.remote_sql)
  ) %}
  {% do dbt_unittest.assert_equals(
    _ir_fixture_column_names(alloydb),
    _ir_fixture_column_names(pg)
  ) %}
{% endmacro %}

{% macro test_plan_from_ir_alloydb_orders() %}
  {% set fixture = ir_fixture_alloydb_orders() %}
  {% set result = _ir_fixture_plan(fixture) %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.provider, 'alloydb_postgres') %}
  {% do dbt_unittest.assert_equals(result.plan.body, fixture.expected.body) %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, fixture.expected.pushdown) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    fixture.expected.remote_sql
  ) %}
{% endmacro %}

{% macro test_plan_from_ir_spanner_type_matrix() %}
  {% set fixture = ir_fixture_spanner_type_matrix() %}
  {% set result = _ir_fixture_plan(fixture) %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, fixture.expected.body) %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, fixture.expected.pushdown) %}
  {% do dbt_unittest.assert_equals(result.plan.query_execution_priority, fixture.expected.query_execution_priority) %}
  {% do dbt_unittest.assert_equals(result.plan.remote_sql, fixture.expected.remote_sql) %}
  {% for col_name in fixture.expected.passthrough %}
    {% do _ir_fixture_assert_column_action(result.plan, col_name, 'passthrough') %}
  {% endfor %}
{% endmacro %}

{% macro test_plan_from_ir_spanner_orders_native() %}
  {% set fixture = ir_fixture_spanner_orders_native() %}
  {% set result = _ir_fixture_plan(fixture) %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, fixture.expected.body) %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, fixture.expected.pushdown) %}
  {% do dbt_unittest.assert_equals(result.plan.query_execution_priority, fixture.expected.query_execution_priority) %}
  {% do dbt_unittest.assert_equals(result.plan.remote_sql, fixture.expected.remote_sql) %}
{% endmacro %}

{% macro test_plan_from_ir_spanner_struct_still_fails() %}
  {% set conn = _ir_fixture_connection(
    'spanner_google_sql',
    'spanner_app',
    'projects/p/locations/us/connections/spanner'
  ) %}
  {% set result = dbt_bigquery_federation._federation_try_plan_columns(
    conn, '', 'Orders', [{'name': 'payload', 'data_type': 'STRUCT<id INT64>'}], none, none, 'live'
  ) %}
  {% do dbt_unittest.assert_equals(result.ok, false) %}
  {% do dbt_unittest.assert_equals('unsupported type' in result.error, true) %}
  {% do dbt_unittest.assert_equals('STRUCT<id INT64>' in result.error, true) %}
{% endmacro %}

{% macro test_plan_from_ir_postgres_udt_uuid() %}
  {% set conn = _ir_fixture_connection(
    'cloud_sql_postgres',
    'application_pg',
    'projects/p/locations/us/connections/pg'
  ) %}
  {% set columns = [{'name': 'user_uuid', 'data_type': 'USER-DEFINED', 'udt_name': 'uuid'}] %}
  {% set result = dbt_bigquery_federation._federation_try_plan_columns(conn, 'public', 'users', columns, none, none, 'live') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].source_type, 'uuid') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].action, 'remote_cast') %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    'select cast("user_uuid" as text) as "user_uuid" from "public"."users"'
  ) %}
{% endmacro %}
