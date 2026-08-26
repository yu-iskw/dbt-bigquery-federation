{# Normalized IR for Spanner GoogleSQL TypeMatrix (e2e/fixtures/spanner_type_matrix.sql). #}

{% macro ir_fixture_spanner_type_matrix() %}
  {% set columns = [
    {'name': 'Id', 'data_type': 'INT64', 'ordinal_position': 1, 'nullable': false},
    {'name': 'ColBool', 'data_type': 'BOOL', 'ordinal_position': 2, 'nullable': false},
    {'name': 'ColBytes', 'data_type': 'BYTES', 'ordinal_position': 3, 'nullable': false},
    {'name': 'ColDate', 'data_type': 'DATE', 'ordinal_position': 4, 'nullable': false},
    {'name': 'ColFloat', 'data_type': 'FLOAT64', 'ordinal_position': 5, 'nullable': false},
    {'name': 'ColJson', 'data_type': 'JSON', 'ordinal_position': 6, 'nullable': false},
    {'name': 'ColNumeric', 'data_type': 'NUMERIC', 'ordinal_position': 7, 'nullable': false},
    {'name': 'ColString', 'data_type': 'STRING', 'ordinal_position': 8, 'nullable': false},
    {'name': 'ColTimestamp', 'data_type': 'TIMESTAMP', 'ordinal_position': 9, 'nullable': false},
    {'name': 'ColArray', 'data_type': 'ARRAY<STRING>', 'ordinal_position': 10, 'nullable': true}
  ] %}
  {{ return({
    'provider_family': 'spanner_google',
    'schema': '',
    'table': 'TypeMatrix',
    'connection': _ir_fixture_connection(
      'spanner_google_sql',
      'spanner_app',
      'projects/p/locations/us/connections/spanner',
      'safe',
      'low'
    ),
    'columns': columns,
    'expected': {
      'body': 'passthrough',
      'pushdown': 'kept',
      'passthrough': [
        'Id', 'ColBool', 'ColBytes', 'ColDate', 'ColFloat', 'ColJson',
        'ColNumeric', 'ColString', 'ColTimestamp', 'ColArray'
      ],
      'remote_cast': [],
      'remote_sql': 'select * from `TypeMatrix`',
      'query_execution_priority': 'low'
    }
  }) }}
{% endmacro %}

{% macro ir_fixture_spanner_orders_native() %}
  {{ return({
    'provider_family': 'spanner_google',
    'schema': '',
    'table': 'Orders',
    'connection': _ir_fixture_connection(
      'spanner_google_sql',
      'spanner_app',
      'projects/p/locations/us/connections/spanner',
      'safe',
      'low'
    ),
    'columns': [
      {'name': 'id', 'data_type': 'INT64'},
      {'name': 'payload', 'data_type': 'JSON'},
      {'name': 'created_at', 'data_type': 'TIMESTAMP'}
    ],
    'expected': {
      'body': 'passthrough',
      'pushdown': 'kept',
      'remote_sql': 'select * from `Orders`',
      'query_execution_priority': 'low'
    }
  }) }}
{% endmacro %}
