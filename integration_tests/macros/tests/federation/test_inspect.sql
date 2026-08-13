{% macro test_federation_inspect_reports_pushdown() %}
  {% set kept = dbt_bigquery_federation._federation_inspect_result('application_pg', 'public', 'orders') %}
  {% do dbt_unittest.assert_equals(kept.ok, true) %}
  {% do dbt_unittest.assert_equals(kept.plan.pushdown, 'kept') %}
  {% do dbt_unittest.assert_equals('pushdown=kept' in kept.report, true) %}

  {% set lost = dbt_bigquery_federation._federation_inspect_result('application_pg', 'public', 'users') %}
  {% do dbt_unittest.assert_equals(lost.ok, true) %}
  {% do dbt_unittest.assert_equals(lost.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals('pushdown=lost' in lost.report, true) %}
  {% do dbt_unittest.assert_equals('user_uuid' in lost.report, true) %}
{% endmacro %}
