{% macro test_plan_all_native_passthrough() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('application_pg', 'orders', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'passthrough') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'kept') %}
  {% do dbt_unittest.assert_equals(result.plan.decimal_option, none) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    'select * from "public"."orders"'
  ) %}
  {% do dbt_unittest.assert_equals(result.plan.warnings, []) %}
{% endmacro %}

{% macro test_plan_uuid_jsonb_safe_projection() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('application_pg', 'users', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    'select "id", cast("user_uuid" as text) as "user_uuid", cast("payload" as text) as "payload" from "public"."users"'
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
    'public'
  ) %}
  {% do dbt_unittest.assert_equals(result.ok, false) %}
{% endmacro %}

{% macro test_plan_bounded_numeric_passthrough() %}
  {% set result = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'amounts',
    'public'
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
    'select "amount", cast("ratio" as text) as "ratio" from "public"."mixed_decimals"'
  ) %}
  {% set amount_col = result.plan.columns[0] %}
  {% do dbt_unittest.assert_equals(amount_col.name, 'amount') %}
  {% do dbt_unittest.assert_equals(amount_col.action, 'passthrough') %}
  {% set ratio_col = result.plan.columns[1] %}
  {% do dbt_unittest.assert_equals(ratio_col.name, 'ratio') %}
  {% do dbt_unittest.assert_equals(ratio_col.action, 'remote_cast') %}
  {% do dbt_unittest.assert_equals(
    result.plan.warnings,
    ['One or more decimal columns cannot be proven to fit BIGNUMERIC; those columns are remote-cast to text and pushdown is lost.']
  ) %}
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

{% macro test_plan_mixed_bignumeric_and_unbounded_keeps_option() %}
  {% set result = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'wide_decimals',
    'public'
  ) %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals(result.plan.decimal_option, 'bignumeric') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].action, 'passthrough') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].target_type, 'BIGNUMERIC') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[1].action, 'remote_cast') %}
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

{% macro test_plan_type_overrides_money_under_strict() %}
  {% set result = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'prices',
    'public',
    'strict'
  ) %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].action, 'remote_cast') %}
{% endmacro %}

{% macro test_plan_empty_and_duplicate_pins_error() %}
  {% set empty = dbt_bigquery_federation._federation_try_plan('application_pg', 'empty', 'public') %}
  {% do dbt_unittest.assert_equals(empty.ok, false) %}
  {% set dup = dbt_bigquery_federation._federation_try_plan('application_pg', 'duplicates', 'public') %}
  {% do dbt_unittest.assert_equals(dup.ok, false) %}
{% endmacro %}

{% macro test_plan_bit_native_passthrough() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('application_pg', 'bits', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'passthrough') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'kept') %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    'select * from "public"."bits"'
  ) %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].name, 'flags') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].source_type, 'bit') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].action, 'passthrough') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].target_type, 'BYTES') %}
{% endmacro %}

{% macro test_plan_varbit_and_bit_typmod_native_passthrough() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('application_pg', 'bits', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'passthrough') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[1].name, 'packed') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[1].source_type, 'bit varying') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[1].action, 'passthrough') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[1].target_type, 'BYTES') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[2].name, 'masked') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[2].source_type, 'bit') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[2].action, 'passthrough') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[2].target_type, 'BYTES') %}
{% endmacro %}

{% macro test_plan_pg_lsn_safe_remote_cast() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('application_pg', 'pg_lsn_types', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].action, 'remote_cast') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].remote_type, 'text') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].target_type, 'STRING') %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    'select cast("lsn" as text) as "lsn" from "public"."pg_lsn_types"'
  ) %}
{% endmacro %}

{% macro test_plan_search_types_safe_remote_cast() %}
  {% set result = dbt_bigquery_federation._federation_try_plan('application_pg', 'search_types', 'public') %}
  {% do dbt_unittest.assert_equals(result.ok, true) %}
  {% do dbt_unittest.assert_equals(result.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(result.plan.pushdown, 'lost') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].action, 'remote_cast') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[0].remote_type, 'text') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[1].action, 'remote_cast') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[1].remote_type, 'text') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[2].action, 'remote_cast') %}
  {% do dbt_unittest.assert_equals(result.plan.columns[2].remote_type, 'text') %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(result.plan.remote_sql),
    'select cast("query" as text) as "query", cast("vector" as text) as "vector", cast("snapshot" as text) as "snapshot" from "public"."search_types"'
  ) %}
{% endmacro %}

{% macro test_plan_integer_array_unknown_errors() %}
  {% set safe = dbt_bigquery_federation._federation_try_plan('application_pg', 'int_array', 'public') %}
  {% do dbt_unittest.assert_equals(safe.ok, false) %}
  {% do dbt_unittest.assert_equals('unknown type' in safe.error, true) %}
  {% do dbt_unittest.assert_equals('type override' in safe.error, true) %}
  {% set strict = dbt_bigquery_federation._federation_try_plan(
    'application_pg',
    'int_array',
    'public',
    'strict'
  ) %}
  {% do dbt_unittest.assert_equals(strict.ok, false) %}
  {% do dbt_unittest.assert_equals('unknown type' in strict.error, true) %}
  {% do dbt_unittest.assert_equals('type override' in strict.error, true) %}
{% endmacro %}

{% macro test_plan_json_native_passthrough() %}
  {% set native = dbt_bigquery_federation._federation_try_plan('application_pg', 'json_native', 'public') %}
  {% do dbt_unittest.assert_equals(native.ok, true) %}
  {% do dbt_unittest.assert_equals(native.plan.body, 'passthrough') %}
  {% do dbt_unittest.assert_equals(native.plan.pushdown, 'kept') %}
  {% do dbt_unittest.assert_equals(native.plan.columns[0].action, 'passthrough') %}
  {% do dbt_unittest.assert_equals(native.plan.columns[0].target_type, 'STRING') %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(native.plan.remote_sql),
    'select * from "public"."json_native"'
  ) %}
  {% set jsonb_pin = dbt_bigquery_federation._federation_try_plan('application_pg', 'users', 'public') %}
  {% do dbt_unittest.assert_equals(jsonb_pin.ok, true) %}
  {% do dbt_unittest.assert_equals(jsonb_pin.plan.body, 'projection') %}
  {% do dbt_unittest.assert_equals(jsonb_pin.plan.columns[2].name, 'payload') %}
  {% do dbt_unittest.assert_equals(jsonb_pin.plan.columns[2].source_type, 'jsonb') %}
  {% do dbt_unittest.assert_equals(jsonb_pin.plan.columns[2].action, 'remote_cast') %}
{% endmacro %}
