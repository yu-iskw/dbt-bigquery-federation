{% macro test_federation_inspect_reports_pushdown() %}
  {% set kept = dbt_bigquery_federation._federation_inspect_result('application_pg', 'public', 'orders') %}
  {% do dbt_unittest.assert_equals(kept.ok, true) %}
  {% do dbt_unittest.assert_equals(kept.plan.pushdown, 'kept') %}
  {% do dbt_unittest.assert_equals('pushdown=kept' in kept.report, true) %}
  {% do dbt_unittest.assert_equals(kept.plan.columns[0].action, 'passthrough') %}
  {% do dbt_unittest.assert_equals(kept.plan.columns[0].lossiness, 'exact') %}

  {% set lost = dbt_bigquery_federation._federation_inspect_result('application_pg', 'public', 'users') %}
  {% do dbt_unittest.assert_equals(lost.ok, true) %}
  {% do dbt_unittest.assert_equals(lost.plan.policy, 'safe') %}
  {% do dbt_unittest.assert_equals(lost.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(lost.plan.pushdown, 'lost') %}
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
  {% do dbt_unittest.assert_equals('id\tbigint\tINT64\tpassthrough\texact\tkept' in lost.report, true) %}
  {% do dbt_unittest.assert_equals('user_uuid\tuuid\tSTRING\tremote_cast\trepresentation_change\tlost' in lost.report, true) %}
  {% do dbt_unittest.assert_equals('payload\tjsonb\tSTRING\tremote_cast\trepresentation_change\tlost' in lost.report, true) %}

  {% set live = dbt_bigquery_federation._federation_inspect_result('application_pg', 'public', 'orders', true) %}
  {% do dbt_unittest.assert_equals(live.ok, false) %}
{% endmacro %}

{% macro test_federation_inspect_strict_requires_overrides() %}
  {# Package type_overrides.UUID covers user_uuid; jsonb payload is the first strict failure. #}
  {% set strict = dbt_bigquery_federation._federation_inspect_result(
    'application_pg',
    'public',
    'users',
    false,
    'strict'
  ) %}
  {% do dbt_unittest.assert_equals(strict.ok, false) %}
  {% do dbt_unittest.assert_equals('cloud_sql_postgres' in strict.error, true) %}
  {% do dbt_unittest.assert_equals('users' in strict.error, true) %}
  {% do dbt_unittest.assert_equals('payload' in strict.error, true) %}
  {% do dbt_unittest.assert_equals('jsonb' in strict.error, true) %}
  {% do dbt_unittest.assert_equals('strict' in strict.error, true) %}
  {% do dbt_unittest.assert_equals('type_overrides' in strict.error, true) %}
  {% do dbt_unittest.assert_equals('pin strategy' in strict.error, true) %}

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

{% macro test_federation_inspect_missing_pin_and_unknown_type_errors() %}
  {% set missing = dbt_bigquery_federation._federation_inspect_result(
    'application_pg',
    'public',
    'does_not_exist'
  ) %}
  {% do dbt_unittest.assert_equals(missing.ok, false) %}
  {% do dbt_unittest.assert_equals('application_pg' in missing.error, true) %}
  {% do dbt_unittest.assert_equals('application_pg.public.does_not_exist' in missing.error, true) %}

  {% set unknown = dbt_bigquery_federation._federation_inspect_result(
    'application_pg',
    'public',
    'mystery'
  ) %}
  {% do dbt_unittest.assert_equals(unknown.ok, false) %}
  {% do dbt_unittest.assert_equals('citext' in unknown.error, true) %}
  {% do dbt_unittest.assert_equals('type_overrides' in unknown.error, true) %}
  {% do dbt_unittest.assert_equals('pin strategy' in unknown.error, true) %}
{% endmacro %}
