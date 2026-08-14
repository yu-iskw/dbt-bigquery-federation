{% macro test_federation_inspect_reports_pushdown() %}
  {% set kept = dbt_bigquery_federation._federation_inspect_result('application_pg', 'public', 'orders') %}
  {% do dbt_unittest.assert_equals(kept.ok, true) %}
  {% do dbt_unittest.assert_equals(kept.plan.pushdown, 'kept') %}
  {% do dbt_unittest.assert_equals('pushdown=kept' in kept.report, true) %}
  {% do dbt_unittest.assert_equals(kept.plan.columns[0].action, 'passthrough') %}
  {% do dbt_unittest.assert_equals(kept.plan.columns[0].lossiness, 'exact') %}

  {% set lost = dbt_bigquery_federation._federation_inspect_result('application_pg', 'public', 'users') %}
  {% do dbt_unittest.assert_equals(lost.ok, true) %}
  {% do dbt_unittest.assert_equals(lost.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals('pushdown=lost' in lost.report, true) %}
  {% do dbt_unittest.assert_equals('user_uuid' in lost.report, true) %}
  {% set found = namespace(uuid=none) %}
  {% for col in lost.plan.columns %}
    {% if col.name == 'user_uuid' %}
      {% set found.uuid = col %}
    {% endif %}
  {% endfor %}
  {% do dbt_unittest.assert_equals(found.uuid.action, 'remote_cast') %}
  {% do dbt_unittest.assert_equals(found.uuid.lossiness, 'representation_change') %}
  {% do dbt_unittest.assert_equals('id\tbigint\tINT64\tpassthrough\texact\tkept' in lost.report, true) %}
  {% do dbt_unittest.assert_equals('user_uuid\tuuid\tSTRING\tremote_cast\trepresentation_change\tlost' in lost.report, true) %}

  {% set live = dbt_bigquery_federation._federation_inspect_result('application_pg', 'public', 'orders', true) %}
  {% do dbt_unittest.assert_equals(live.ok, false) %}
{% endmacro %}
