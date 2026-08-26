{# Live GCP e2e assertions for type_matrix tables.
   Invoked only from e2e/run.sh against --target bigquery_gcp. #}

{% macro assert_e2e_type_matrices() %}
  {% if not execute %}
    {{ return('') }}
  {% endif %}
  {% do _assert_e2e_alloydb_type_matrix() %}
  {% do _assert_e2e_spanner_type_matrix() %}
  {% do log('E2E type_matrix assertions passed for AlloyDB and Spanner', info=True) %}
{% endmacro %}

{% macro _assert_e2e_expect_columns(discovered, expected_names) %}
  {% set found = [] %}
  {% set found_lower = [] %}
  {% for col in discovered.columns %}
    {% do found.append(col.name | string) %}
    {% do found_lower.append(col.name | string | lower) %}
  {% endfor %}
  {% for expected in expected_names %}
    {% if (expected | lower) not in found_lower %}
      {{ exceptions.raise_compiler_error('E2E metadata missing column ' ~ expected ~ '; discovered=' ~ (found | join(','))) }}
    {% endif %}
  {% endfor %}
{% endmacro %}

{% macro _assert_e2e_column_action(plan, column_name, expected_action) %}
  {% set matched = namespace(found=false) %}
  {% for col in plan.columns %}
    {% if (col.name | string | lower) == (column_name | lower) %}
      {% set matched.found = true %}
      {% if col.action != expected_action %}
        {{ exceptions.raise_compiler_error(
          'E2E column ' ~ column_name ~ ' expected action=' ~ expected_action ~ ' got ' ~ col.action
        ) }}
      {% endif %}
    {% endif %}
  {% endfor %}
  {% if not matched.found %}
    {{ exceptions.raise_compiler_error('E2E plan missing column ' ~ column_name) }}
  {% endif %}
{% endmacro %}

{% macro _assert_e2e_alloydb_type_matrix() %}
  {# Column contract shared with offline IR fixture (macros/tests/fixtures/ir/). #}
  {% set fixture = ir_fixture_alloydb_type_matrix() %}
  {% set expected_columns = _ir_fixture_column_names(fixture) %}
  {% set discovered = dbt_bigquery_federation._federation_try_get_remote_columns('analytics_alloydb', 'type_matrix', 'public') %}
  {% if not discovered.ok %}
    {{ exceptions.raise_compiler_error('AlloyDB type_matrix discovery failed: ' ~ discovered.error) }}
  {% endif %}
  {% do _assert_e2e_expect_columns(discovered, expected_columns) %}

  {% set planned = dbt_bigquery_federation._federation_try_plan_live('analytics_alloydb', 'type_matrix', 'public') %}
  {% if not planned.ok %}
    {{ exceptions.raise_compiler_error('AlloyDB type_matrix live plan failed: ' ~ planned.error) }}
  {% endif %}
  {% do dbt_unittest.assert_equals(planned.plan.body, fixture.expected.body) %}
  {% do dbt_unittest.assert_equals(planned.plan.pushdown, fixture.expected.pushdown) %}
  {% for col_name in fixture.expected.passthrough %}
    {% do _assert_e2e_column_action(planned.plan, col_name, 'passthrough') %}
  {% endfor %}
  {% for col_name in fixture.expected.remote_cast %}
    {% do _assert_e2e_column_action(planned.plan, col_name, 'remote_cast') %}
  {% endfor %}

  {% set relation_sql = dbt_bigquery_federation._federation_render_external_query(
    planned.plan.connection_id,
    planned.plan.remote_sql,
    planned.plan.decimal_option,
    planned.plan.get('query_execution_priority')
  ) %}
  {% set rows = run_query(
    "select id, col_boolean, cast(col_numeric as string) as col_numeric, col_text, col_uuid, col_jsonb, col_inet from "
    ~ relation_sql
  ) %}
  {% if rows is none or rows.rows | length != 1 %}
    {{ exceptions.raise_compiler_error('AlloyDB type_matrix live EXTERNAL_QUERY expected 1 row') }}
  {% endif %}
  {% set row = rows.rows[0] %}
  {% do dbt_unittest.assert_equals(row[0] | int, 1) %}
  {% if row[1] is not true and (row[1] | string | lower) not in ['true', '1'] %}
    {{ exceptions.raise_compiler_error('AlloyDB col_boolean unexpected value: ' ~ (row[1] | string)) }}
  {% endif %}
  {% do dbt_unittest.assert_equals(row[2] | string, '12.34') %}
  {% do dbt_unittest.assert_equals(row[3] | string, 'hello') %}
  {% do dbt_unittest.assert_equals(row[4] | string, '11111111-1111-1111-1111-111111111111') %}
  {% if '"active": true' not in (row[5] | string) and '"active":true' not in (row[5] | string) %}
    {{ exceptions.raise_compiler_error('AlloyDB col_jsonb unexpected value: ' ~ (row[5] | string)) }}
  {% endif %}
  {% if '127.0.0.1' not in (row[6] | string) %}
    {{ exceptions.raise_compiler_error('AlloyDB col_inet unexpected value: ' ~ (row[6] | string)) }}
  {% endif %}
{% endmacro %}

{% macro _assert_e2e_spanner_type_matrix() %}
  {% set fixture = ir_fixture_spanner_type_matrix() %}
  {% set expected_columns = _ir_fixture_column_names(fixture) %}
  {% set discovered = dbt_bigquery_federation._federation_try_get_remote_columns('spanner_app', 'TypeMatrix', '') %}
  {% if not discovered.ok %}
    {{ exceptions.raise_compiler_error('Spanner TypeMatrix discovery failed: ' ~ discovered.error) }}
  {% endif %}
  {% do _assert_e2e_expect_columns(discovered, expected_columns) %}

  {% set planned = dbt_bigquery_federation._federation_try_plan_live('spanner_app', 'TypeMatrix', '') %}
  {% if not planned.ok %}
    {{ exceptions.raise_compiler_error('Spanner TypeMatrix live plan failed: ' ~ planned.error) }}
  {% endif %}
  {% do dbt_unittest.assert_equals(planned.plan.body, fixture.expected.body) %}
  {% do dbt_unittest.assert_equals(planned.plan.pushdown, fixture.expected.pushdown) %}
  {% for col_name in fixture.expected.passthrough %}
    {% do _assert_e2e_column_action(planned.plan, col_name, 'passthrough') %}
  {% endfor %}

  {% set relation_sql = dbt_bigquery_federation._federation_render_external_query(
    planned.plan.connection_id,
    planned.plan.remote_sql,
    planned.plan.decimal_option,
    planned.plan.get('query_execution_priority')
  ) %}
  {% set rows = run_query(
    "select Id, ColBool, cast(ColNumeric as string) as ColNumeric, ColString, to_json_string(ColJson) as ColJson, array_length(ColArray) as array_len from "
    ~ relation_sql
  ) %}
  {% if rows is none or rows.rows | length != 1 %}
    {{ exceptions.raise_compiler_error('Spanner TypeMatrix live EXTERNAL_QUERY expected 1 row') }}
  {% endif %}
  {% set row = rows.rows[0] %}
  {% do dbt_unittest.assert_equals(row[0] | int, 1) %}
  {% if row[1] is not true and (row[1] | string | lower) not in ['true', '1'] %}
    {{ exceptions.raise_compiler_error('Spanner ColBool unexpected value: ' ~ (row[1] | string)) }}
  {% endif %}
  {% do dbt_unittest.assert_equals(row[2] | string, '12.34') %}
  {% do dbt_unittest.assert_equals(row[3] | string, 'alpha') %}
  {% if 'spanner' not in (row[4] | string) %}
    {{ exceptions.raise_compiler_error('Spanner ColJson unexpected value: ' ~ (row[4] | string)) }}
  {% endif %}
  {% do dbt_unittest.assert_equals(row[5] | int, 2) %}
{% endmacro %}
