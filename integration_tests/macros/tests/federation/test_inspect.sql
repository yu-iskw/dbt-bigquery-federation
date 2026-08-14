{% macro test_federation_inspect_reports_pushdown() %}
  {% set kept = dbt_bigquery_federation._federation_inspect_result('application_pg', 'public', 'orders') %}
  {% do dbt_unittest.assert_equals(kept.ok, true) %}
  {% do dbt_unittest.assert_equals(kept.plan.pushdown, 'kept') %}
  {% do dbt_unittest.assert_equals('metadata_source=pinned' in kept.report, true) %}
  {% do dbt_unittest.assert_equals('pushdown=kept' in kept.report, true) %}
  {% do dbt_unittest.assert_equals(kept.plan.columns[0].action, 'passthrough') %}
  {% do dbt_unittest.assert_equals(kept.plan.columns[0].lossiness, 'exact') %}

  {% set lost = dbt_bigquery_federation._federation_inspect_result('application_pg', 'public', 'users') %}
  {% do dbt_unittest.assert_equals(lost.ok, true) %}
  {% do dbt_unittest.assert_equals(lost.plan.policy, 'safe') %}
  {% do dbt_unittest.assert_equals(lost.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(lost.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals('metadata_source=pinned' in lost.report, true) %}
  {% do dbt_unittest.assert_equals('policy=safe' in lost.report, true) %}
  {% do dbt_unittest.assert_equals('pushdown=lost' in lost.report, true) %}
  {% do dbt_unittest.assert_equals('user_uuid' in lost.report, true) %}
  {% set found = namespace(uuid=none, payload=none) %}
  {% for col in lost.plan.columns %}
    {% if col.name == 'user_uuid' %}
      {% set found.uuid = col %}
    {% endif %}
    {% if col.name == 'payload' %}
      {% set found.payload = col %}
    {% endif %}
  {% endfor %}
  {% do dbt_unittest.assert_equals(found.uuid.action, 'remote_cast') %}
  {% do dbt_unittest.assert_equals(found.uuid.lossiness, 'representation_change') %}
  {% do dbt_unittest.assert_equals(found.payload.action, 'remote_cast') %}
  {% do dbt_unittest.assert_equals(found.payload.source_type, 'jsonb') %}
  {% do dbt_unittest.assert_equals('id\tbigint\tINT64\tpassthrough\texact\tno' in lost.report, true) %}
  {% do dbt_unittest.assert_equals('user_uuid\tuuid\tSTRING\tremote_cast\trepresentation_change\tyes' in lost.report, true) %}
  {% do dbt_unittest.assert_equals('payload\tjsonb\tSTRING\tremote_cast\trepresentation_change\tyes' in lost.report, true) %}
{% endmacro %}

{% macro test_federation_inspect_strict_requires_overrides() %}
  {# type_policy and overrides sit after live so positional true still means live. #}
  {% set planned = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'users',
    'public',
    'strict'
  ) %}
  {% set strict = dbt_bigquery_federation._federation_inspect_result(
    'application_pg',
    'public',
    'users',
    false,
    'strict'
  ) %}
  {% do dbt_unittest.assert_equals(strict.ok, false) %}
  {% do dbt_unittest.assert_equals(strict.error, planned.error) %}

  {% set overridden = dbt_bigquery_federation._federation_inspect_result(
    'application_pg',
    'public',
    'users',
    false,
    'strict',
    {
      'user_uuid': {'strategy': 'remote_cast', 'remote_type': 'text', 'target_type': 'STRING'},
      'payload': {'strategy': 'remote_cast', 'remote_type': 'text', 'target_type': 'STRING'}
    }
  ) %}
  {% do dbt_unittest.assert_equals(overridden.ok, true) %}
  {% do dbt_unittest.assert_equals(overridden.plan.policy, 'strict') %}
  {% do dbt_unittest.assert_equals(overridden.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals(overridden.plan.body, 'projection') %}
{% endmacro %}

{% macro test_federation_inspect_forwards_plan_errors() %}
  {% set planned_missing = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'does_not_exist',
    'public'
  ) %}
  {% set missing = dbt_bigquery_federation._federation_inspect_result(
    'application_pg',
    'public',
    'does_not_exist'
  ) %}
  {% do dbt_unittest.assert_equals(missing.ok, false) %}
  {% do dbt_unittest.assert_equals(missing.error, planned_missing.error) %}

  {% set planned_unknown = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'mystery',
    'public'
  ) %}
  {% set unknown = dbt_bigquery_federation._federation_inspect_result(
    'application_pg',
    'public',
    'mystery'
  ) %}
  {% do dbt_unittest.assert_equals(unknown.ok, false) %}
  {% do dbt_unittest.assert_equals(unknown.error, planned_unknown.error) %}
{% endmacro %}
