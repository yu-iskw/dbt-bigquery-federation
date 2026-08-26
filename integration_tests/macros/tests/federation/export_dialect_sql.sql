{# Run-operation helpers for Layer 3 dialect pytest.
   Emit DIALECT_EXPORT_PATH / DIALECT_EXPORT_JSON log lines; the pytest harness
   parses stdout and writes JSON under target/dialect/. dbt modules do not
   expose pathlib for direct file writes. #}

{% macro _dialect_default_output_path(filename) %}
  {{ return(target.path ~ '/dialect/' ~ filename) }}
{% endmacro %}

{% macro _dialect_write_json(output_path, payload) %}
  {# dbt's modules whitelist does not include pathlib; pytest parses these log
     lines and writes the JSON file on the host. #}
  {% do log('DIALECT_EXPORT_PATH=' ~ (output_path | string), info=True) %}
  {% do log('DIALECT_EXPORT_JSON=' ~ tojson(payload), info=True) %}
{% endmacro %}

{% macro dialect_export_metadata_remote_sql(provider, schema, table, output_path=none) %}
  {% set out = output_path if output_path is not none else _dialect_default_output_path('metadata_remote_sql.json') %}
  {% set sql = dbt_bigquery_federation._federation_provider_metadata_remote_sql(provider, schema, table) %}
  {% do _dialect_write_json(out, {
    'ok': true,
    'provider': provider,
    'schema': schema,
    'table': table,
    'remote_sql': sql
  }) %}
{% endmacro %}

{% macro _dialect_resolve_ir_fixture(fixture) %}
  {% if fixture == 'postgres_type_matrix' %}
    {{ return(ir_fixture_postgres_type_matrix()) }}
  {% elif fixture == 'alloydb_type_matrix' %}
    {{ return(ir_fixture_alloydb_type_matrix()) }}
  {% elif fixture == 'spanner_type_matrix' %}
    {{ return(ir_fixture_spanner_type_matrix()) }}
  {% elif fixture == 'postgres_orders' %}
    {{ return(ir_fixture_alloydb_orders()) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unknown dialect IR fixture: ' ~ (fixture | string)) }}
{% endmacro %}

{% macro dialect_export_plan_remote_sql(fixture, type_policy=none, overrides=none, output_path=none) %}
  {% set out = output_path if output_path is not none else _dialect_default_output_path('plan_remote_sql.json') %}
  {% set pack = _dialect_resolve_ir_fixture(fixture) %}
  {% set result = _ir_fixture_plan(pack, type_policy, overrides) %}
  {% if not result.ok %}
    {% do _dialect_write_json(out, {
      'ok': false,
      'fixture': fixture,
      'error': result.error,
      'remote_sql': none,
      'body': none,
      'pushdown': none
    }) %}
  {% else %}
    {% do _dialect_write_json(out, {
      'ok': true,
      'fixture': fixture,
      'provider': result.plan.provider,
      'schema': pack.schema,
      'table': pack.table,
      'remote_sql': result.plan.remote_sql,
      'body': result.plan.body,
      'pushdown': result.plan.pushdown,
      'error': none
    }) %}
  {% endif %}
{% endmacro %}

{% macro dialect_normalize_metadata_row_list(provider, rows, fixture=none, output_path=none) %}
  {% set out = output_path if output_path is not none else _dialect_default_output_path('normalize_result.json') %}
  {% set normalized = dbt_bigquery_federation._federation_normalize_metadata_rows(provider, rows) %}
  {% set mismatches = [] %}
  {% set matches_fixture = none %}
  {% if normalized.ok and fixture is not none %}
    {% set pack = _dialect_resolve_ir_fixture(fixture) %}
    {% if (normalized.columns | length) != (pack.columns | length) %}
      {% do mismatches.append('column_count expected=' ~ (pack.columns | length) ~ ' got=' ~ (normalized.columns | length)) %}
    {% else %}
      {% for i in range(pack.columns | length) %}
        {% set expected = pack.columns[i] %}
        {% set actual = normalized.columns[i] %}
        {% if (actual.name | string) != (expected.name | string) %}
          {% do mismatches.append('name[' ~ i ~ '] expected=' ~ expected.name ~ ' got=' ~ actual.name) %}
        {% endif %}
        {% if (actual.ordinal_position | int) != (expected.ordinal_position | int) %}
          {% do mismatches.append('ordinal[' ~ i ~ '] expected=' ~ expected.ordinal_position ~ ' got=' ~ actual.ordinal_position) %}
        {% endif %}
        {% if (actual.data_type | string | upper) != (expected.data_type | string | upper) %}
          {% do mismatches.append('data_type[' ~ expected.name ~ '] expected=' ~ expected.data_type ~ ' got=' ~ actual.data_type) %}
        {% endif %}
        {% if expected.get('nullable') is not none and actual.nullable != expected.nullable %}
          {% do mismatches.append('nullable[' ~ expected.name ~ '] expected=' ~ expected.nullable ~ ' got=' ~ actual.nullable) %}
        {% endif %}
        {% if expected.get('precision') is not none and actual.precision != expected.precision %}
          {% do mismatches.append('precision[' ~ expected.name ~ '] expected=' ~ expected.precision ~ ' got=' ~ actual.precision) %}
        {% endif %}
        {% if expected.get('scale') is not none and actual.scale != expected.scale %}
          {% do mismatches.append('scale[' ~ expected.name ~ '] expected=' ~ expected.scale ~ ' got=' ~ actual.scale) %}
        {% endif %}
        {% if expected.get('character_maximum_length') is not none and actual.character_maximum_length != expected.character_maximum_length %}
          {% do mismatches.append('length[' ~ expected.name ~ '] expected=' ~ expected.character_maximum_length ~ ' got=' ~ actual.character_maximum_length) %}
        {% endif %}
      {% endfor %}
    {% endif %}
    {% set matches_fixture = (mismatches | length) == 0 %}
  {% endif %}
  {% do _dialect_write_json(out, {
    'ok': normalized.ok,
    'error': normalized.error,
    'provider': provider,
    'columns': normalized.columns if normalized.ok else none,
    'fixture': fixture,
    'matches_fixture': matches_fixture,
    'mismatches': mismatches
  }) %}
  {% if matches_fixture == false %}
    {{ exceptions.raise_compiler_error('dialect normalize did not match fixture ' ~ fixture ~ ': ' ~ (mismatches | join('; '))) }}
  {% endif %}
{% endmacro %}
