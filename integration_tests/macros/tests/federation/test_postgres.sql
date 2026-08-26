{# Dual type-mapping contract (Approach 3):
   1) canonical map key → BigQuery target
   2) alias / typmod form → BigQuery target (Google EXTERNAL_QUERY table shape)
   3) unsupported → remote cast type → BigQuery STRING
   Cast SQL smoke stays thin; planner scenarios stay in test_plan.sql. #}

{% macro _test_postgres_expected_type_matrix() %}
  {% set unsupported = {
    'kind': 'unsupported',
    'target': 'STRING',
    'lossiness': 'representation_change',
    'remote_type': 'text'
  } %}
  {% set matrix = {
    'smallint': {'kind': 'native', 'target': 'INT64', 'lossiness': 'exact', 'remote_type': 'text'},
    'integer': {'kind': 'native', 'target': 'INT64', 'lossiness': 'exact', 'remote_type': 'text'},
    'bigint': {'kind': 'native', 'target': 'INT64', 'lossiness': 'exact', 'remote_type': 'text'},
    'real': {'kind': 'native', 'target': 'FLOAT64', 'lossiness': 'exact', 'remote_type': 'text'},
    'double precision': {'kind': 'native', 'target': 'FLOAT64', 'lossiness': 'exact', 'remote_type': 'text'},
    'boolean': {'kind': 'native', 'target': 'BOOL', 'lossiness': 'exact', 'remote_type': 'text'},
    'text': {'kind': 'native', 'target': 'STRING', 'lossiness': 'exact', 'remote_type': 'text'},
    'character varying': {'kind': 'native', 'target': 'STRING', 'lossiness': 'exact', 'remote_type': 'text'},
    'character': {'kind': 'native', 'target': 'STRING', 'lossiness': 'exact', 'remote_type': 'text'},
    'name': {'kind': 'native', 'target': 'STRING', 'lossiness': 'exact', 'remote_type': 'text'},
    'bytea': {'kind': 'native', 'target': 'BYTES', 'lossiness': 'exact', 'remote_type': 'text'},
    'date': {'kind': 'native', 'target': 'DATE', 'lossiness': 'exact', 'remote_type': 'text'},
    'timestamp without time zone': {'kind': 'native', 'target': 'DATETIME', 'lossiness': 'exact', 'remote_type': 'text'},
    'timestamp with time zone': {'kind': 'native', 'target': 'TIMESTAMP', 'lossiness': 'exact', 'remote_type': 'text'},
    'time': {'kind': 'native', 'target': 'TIME', 'lossiness': 'exact', 'remote_type': 'text'},
    'time without time zone': {'kind': 'native', 'target': 'TIME', 'lossiness': 'exact', 'remote_type': 'text'},
    'json': {'kind': 'native', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'xml': {'kind': 'native', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'bit': {'kind': 'native', 'target': 'BYTES', 'lossiness': 'exact', 'remote_type': 'text'},
    'bit varying': {'kind': 'native', 'target': 'BYTES', 'lossiness': 'exact', 'remote_type': 'text'},
    'numeric': {'kind': 'decimal', 'target': 'NUMERIC', 'lossiness': 'exact', 'remote_type': 'text'},
    'uuid': unsupported,
    'jsonb': unsupported,
    'money': unsupported,
    'inet': unsupported,
    'cidr': unsupported,
    'macaddr': unsupported,
    'macaddr8': unsupported,
    'interval': unsupported,
    'time with time zone': unsupported,
    'point': unsupported,
    'line': unsupported,
    'lseg': unsupported,
    'box': unsupported,
    'path': unsupported,
    'polygon': unsupported,
    'circle': unsupported,
    'pg_lsn': unsupported,
    'tsquery': unsupported,
    'tsvector': unsupported,
    'txid_snapshot': unsupported
  } %}
  {{ return(matrix) }}
{% endmacro %}

{% macro test_postgres_type_map_keys_match_expected_matrix() %}
  {% set type_map = dbt_bigquery_federation._postgres_federation_type_map() %}
  {% set expected = _test_postgres_expected_type_matrix() %}
  {% do dbt_unittest.assert_equals(type_map | length, expected | length) %}
  {% for data_type in expected %}
    {% do dbt_unittest.assert_equals(data_type in type_map, true) %}
  {% endfor %}
  {% for data_type in type_map %}
    {% do dbt_unittest.assert_equals(data_type in expected, true) %}
  {% endfor %}
{% endmacro %}

{% macro test_postgres_type_entry_matrix() %}
  {% set expected = _test_postgres_expected_type_matrix() %}
  {% for data_type, want in expected.items() %}
    {% set entry = dbt_bigquery_federation._federation_provider_type_entry('cloud_sql_postgres', data_type) %}
    {% do dbt_unittest.assert_equals(entry.kind, want.kind) %}
    {% do dbt_unittest.assert_equals(entry.target, want.target) %}
    {% do dbt_unittest.assert_equals(entry.lossiness, want.lossiness) %}
    {% do dbt_unittest.assert_equals(entry.remote_type, want.remote_type) %}
    {% do dbt_unittest.assert_equals(entry.data_type, data_type) %}
    {% set alloydb_entry = dbt_bigquery_federation._federation_provider_type_entry('alloydb_postgres', data_type) %}
    {% do dbt_unittest.assert_equals(alloydb_entry.kind, entry.kind) %}
    {% do dbt_unittest.assert_equals(alloydb_entry.target, entry.target) %}
    {% do dbt_unittest.assert_equals(alloydb_entry.lossiness, entry.lossiness) %}
    {% do dbt_unittest.assert_equals(alloydb_entry.remote_type, entry.remote_type) %}
  {% endfor %}
{% endmacro %}

{% macro test_postgres_alias_to_bigquery_target_matrix() %}
  {# Explicit alias → BigQuery target (Google EXTERNAL_QUERY naming). #}
  {% set cases = [
    ['int2', 'smallint', 'INT64', 'native'],
    ['int4', 'integer', 'INT64', 'native'],
    ['int', 'integer', 'INT64', 'native'],
    ['int8', 'bigint', 'INT64', 'native'],
    ['serial', 'integer', 'INT64', 'native'],
    ['bigserial', 'bigint', 'INT64', 'native'],
    ['smallserial', 'smallint', 'INT64', 'native'],
    ['float4', 'real', 'FLOAT64', 'native'],
    ['float8', 'double precision', 'FLOAT64', 'native'],
    ['bool', 'boolean', 'BOOL', 'native'],
    ['varchar', 'character varying', 'STRING', 'native'],
    ['char', 'character', 'STRING', 'native'],
    ['timestamptz', 'timestamp with time zone', 'TIMESTAMP', 'native'],
    ['timetz', 'time with time zone', 'STRING', 'unsupported'],
    ['decimal', 'numeric', 'NUMERIC', 'decimal'],
    ['timestamp', 'timestamp without time zone', 'DATETIME', 'native'],
    ['varbit', 'bit varying', 'BYTES', 'native'],
    ['varchar(32)', 'character varying', 'STRING', 'native'],
    ['char(1)', 'character', 'STRING', 'native'],
    ['bit(8)', 'bit', 'BYTES', 'native']
  ] %}
  {% for case in cases %}
    {% set alias = case[0] %}
    {% set canonical = case[1] %}
    {% set bigquery_type = case[2] %}
    {% set kind = case[3] %}
    {% set normalized = dbt_bigquery_federation._federation_provider_normalize_type_name('cloud_sql_postgres', alias) %}
    {% do dbt_unittest.assert_equals(normalized, canonical) %}
    {% set entry = dbt_bigquery_federation._federation_provider_type_entry('cloud_sql_postgres', alias) %}
    {% do dbt_unittest.assert_equals(entry.data_type, canonical) %}
    {% do dbt_unittest.assert_equals(entry.kind, kind) %}
    {% do dbt_unittest.assert_equals(entry.target, bigquery_type) %}
    {% set alloydb_entry = dbt_bigquery_federation._federation_provider_type_entry('alloydb_postgres', alias) %}
    {% do dbt_unittest.assert_equals(alloydb_entry.target, bigquery_type) %}
    {% do dbt_unittest.assert_equals(alloydb_entry.kind, kind) %}
  {% endfor %}
{% endmacro %}

{% macro test_postgres_post_cast_to_bigquery_target_matrix() %}
  {# Unsupported types remote-cast to a supported PG type that itself maps to BigQuery STRING. #}
  {% set cast_targets = ['text', 'character varying', 'varchar', 'character', 'char'] %}
  {% for cast_target in cast_targets %}
    {% set entry = dbt_bigquery_federation._federation_provider_type_entry('cloud_sql_postgres', cast_target) %}
    {% do dbt_unittest.assert_equals(entry.kind, 'native') %}
    {% do dbt_unittest.assert_equals(entry.target, 'STRING') %}
  {% endfor %}

  {% set unsupported = [
    'uuid', 'jsonb', 'money', 'inet', 'cidr', 'macaddr', 'macaddr8', 'interval',
    'time with time zone', 'point', 'line', 'lseg', 'box', 'path', 'polygon', 'circle',
    'pg_lsn', 'tsquery', 'tsvector', 'txid_snapshot'
  ] %}
  {% for src in unsupported %}
    {% set entry = dbt_bigquery_federation._federation_provider_type_entry('cloud_sql_postgres', src) %}
    {% do dbt_unittest.assert_equals(entry.kind, 'unsupported') %}
    {% do dbt_unittest.assert_equals(entry.remote_type, 'text') %}
    {% do dbt_unittest.assert_equals(entry.target, 'STRING') %}
    {% do dbt_unittest.assert_equals(entry.lossiness, 'representation_change') %}
    {% set cast_as = dbt_bigquery_federation._federation_provider_type_entry('cloud_sql_postgres', entry.remote_type) %}
    {% do dbt_unittest.assert_equals(cast_as.target, entry.target) %}
  {% endfor %}
{% endmacro %}

{% macro test_postgres_numeric_typmod_preserved() %}
  {% set normalized = dbt_bigquery_federation._federation_provider_normalize_type_name('cloud_sql_postgres', 'numeric(12, 2)') %}
  {% do dbt_unittest.assert_equals(normalized, 'numeric(12, 2)') %}
  {% set unknown = dbt_bigquery_federation._federation_provider_type_entry('cloud_sql_postgres', 'numeric(12, 2)') %}
  {% do dbt_unittest.assert_equals(unknown.kind, 'unknown') %}
{% endmacro %}

{% macro test_postgres_unknown_type_entry() %}
  {% set entry = dbt_bigquery_federation._federation_provider_type_entry('cloud_sql_postgres', 'geometry') %}
  {% do dbt_unittest.assert_equals(entry.kind, 'unknown') %}
  {% do dbt_unittest.assert_equals(entry.target, none) %}
  {% do dbt_unittest.assert_equals(entry.lossiness, 'unknown') %}
  {% do dbt_unittest.assert_equals(entry.remote_type, 'text') %}
  {% do dbt_unittest.assert_equals(entry.data_type, 'geometry') %}
{% endmacro %}

{% macro test_postgres_render_remote_cast_smoke() %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_render_remote_cast('cloud_sql_postgres', '"user_uuid"', 'text'),
    'cast("user_uuid" as text)'
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_provider_render_remote_cast('alloydb_postgres', '"user_uuid"', 'text'),
    'cast("user_uuid" as text)'
  ) %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_validate_remote_type('text'), true) %}
  {% do dbt_unittest.assert_equals(dbt_bigquery_federation._federation_validate_remote_type('"text"'), false) %}
{% endmacro %}
