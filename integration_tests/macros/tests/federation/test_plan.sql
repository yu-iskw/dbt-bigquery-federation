{% macro test_plan_all_native_passthrough() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('application_pg', 'orders', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'passthrough') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'kept') %}
  {% do dbt_unittest.assert_equals(result.plan.decimal_option, none) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    'select * from public.orders'
  ) %}
{% endmacro %}

{% macro test_plan_uuid_jsonb_safe_projection() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('application_pg', 'users', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    'select id, cast(user_uuid as text) as user_uuid, cast(payload as text) as payload from public.users'
  ) %}
{% endmacro %}

{% macro test_plan_uuid_strict_errors() %}
  {% set result = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'users',
    'public',
    'strict'
  ) %}
  {% do dbt_unittest.assert_equals(result.ok, false) %}
{% endmacro %}

{% macro test_plan_unknown_type_errors() %}
  {% set result = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'mystery',
    'public',
    none,
    none,
    [{'name': 'payload', 'data_type': 'citext'}]
  ) %}
  {% do dbt_unittest.assert_equals(result.ok, false) %}
{% endmacro %}

{% macro test_plan_bounded_numeric_passthrough() %}
  {% set result = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'amounts',
    'public',
    none,
    none,
    [
      {'name': 'amount', 'data_type': 'numeric', 'precision': 12, 'scale': 2}
    ]
  ) %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'passthrough') %}
  {% do dbt_unittest.assert_equals(result.plan.decimal_option, none) %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'kept') %}
{% endmacro %}

{% macro test_plan_mixed_decimals_safe_projects_offender() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('application_pg', 'mixed_decimals', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals(result.plan.decimal_option, none) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    'select amount, cast(ratio as text) as ratio from public.mixed_decimals'
  ) %}
  {% set amount_col = result.plan.columns[0] %}
  {% do dbt_unittest.assert_equals(amount_col.name, 'amount') %}
  {% do dbt_unittest.assert_equals(amount_col.action, 'passthrough') %}
  {% set ratio_col = result.plan.columns[1] %}
  {% do dbt_unittest.assert_equals(ratio_col.name, 'ratio') %}
  {% do dbt_unittest.assert_equals(ratio_col.action, 'remote_cast') %}
{% endmacro %}

{% macro test_plan_mixed_decimals_strict_errors() %}
  {% set result = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'mixed_decimals',
    'public',
    'strict'
  ) %}
  {% do dbt_unittest.assert_equals(result.ok, false) %}
{% endmacro %}

{% macro test_plan_uuid_override_remote_cast() %}
  {% set result = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'users',
    'public',
    'strict',
    {
      'user_uuid': {'strategy': 'remote_cast', 'remote_type': 'text', 'target_type': 'STRING'},
      'payload': {'strategy': 'remote_cast', 'remote_type': 'text', 'target_type': 'STRING'}
    }
  ) %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'projection') %}
{% endmacro %}

{% macro test_plan_missing_pin_errors() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('application_pg', 'does_not_exist', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, false) %}
{% endmacro %}
