{# Normalized IR for the shared postgres_federation type_matrix used by AlloyDB e2e
   (e2e/fixtures/alloydb.sql). cloud_sql_postgres and alloydb_postgres share this pack. #}

{% macro ir_fixture_postgres_type_matrix(provider='cloud_sql_postgres', alias='application_pg', connection_id='projects/p/locations/us/connections/pg') %}
  {% set columns = [
    {'name': 'id', 'data_type': 'bigint', 'ordinal_position': 1, 'nullable': false},
    {'name': 'col_smallint', 'data_type': 'smallint', 'ordinal_position': 2, 'nullable': false},
    {'name': 'col_integer', 'data_type': 'integer', 'ordinal_position': 3, 'nullable': false},
    {'name': 'col_real', 'data_type': 'real', 'ordinal_position': 4, 'nullable': false},
    {'name': 'col_double', 'data_type': 'double precision', 'ordinal_position': 5, 'nullable': false},
    {'name': 'col_boolean', 'data_type': 'boolean', 'ordinal_position': 6, 'nullable': false},
    {'name': 'col_text', 'data_type': 'text', 'ordinal_position': 7, 'nullable': false},
    {'name': 'col_varchar', 'data_type': 'character varying', 'ordinal_position': 8, 'nullable': false, 'character_maximum_length': 32},
    {'name': 'col_char', 'data_type': 'character', 'ordinal_position': 9, 'nullable': false, 'character_maximum_length': 1},
    {'name': 'col_bytea', 'data_type': 'bytea', 'ordinal_position': 10, 'nullable': false},
    {'name': 'col_date', 'data_type': 'date', 'ordinal_position': 11, 'nullable': false},
    {'name': 'col_timestamp', 'data_type': 'timestamp without time zone', 'ordinal_position': 12, 'nullable': false},
    {'name': 'col_timestamptz', 'data_type': 'timestamp with time zone', 'ordinal_position': 13, 'nullable': false},
    {'name': 'col_time', 'data_type': 'time without time zone', 'ordinal_position': 14, 'nullable': false},
    {'name': 'col_json', 'data_type': 'json', 'ordinal_position': 15, 'nullable': false},
    {'name': 'col_xml', 'data_type': 'xml', 'ordinal_position': 16, 'nullable': false},
    {'name': 'col_bit', 'data_type': 'bit', 'ordinal_position': 17, 'nullable': false, 'character_maximum_length': 8},
    {'name': 'col_varbit', 'data_type': 'bit varying', 'ordinal_position': 18, 'nullable': false},
    {'name': 'col_numeric', 'data_type': 'numeric', 'ordinal_position': 19, 'nullable': false, 'precision': 12, 'scale': 2},
    {'name': 'col_uuid', 'data_type': 'uuid', 'ordinal_position': 20, 'nullable': false},
    {'name': 'col_jsonb', 'data_type': 'jsonb', 'ordinal_position': 21, 'nullable': false},
    {'name': 'col_inet', 'data_type': 'inet', 'ordinal_position': 22, 'nullable': false},
    {'name': 'col_interval', 'data_type': 'interval', 'ordinal_position': 23, 'nullable': false}
  ] %}
  {{ return({
    'provider_family': 'postgres_federation',
    'schema': 'public',
    'table': 'type_matrix',
    'connection': _ir_fixture_connection(provider, alias, connection_id, 'safe', none),
    'columns': columns,
    'expected': {
      'body': 'projection',
      'pushdown': 'lost',
      'passthrough': [
        'id', 'col_smallint', 'col_integer', 'col_real', 'col_double', 'col_boolean',
        'col_text', 'col_varchar', 'col_char', 'col_bytea',
        'col_date', 'col_timestamp', 'col_timestamptz', 'col_time',
        'col_json', 'col_xml', 'col_bit', 'col_varbit', 'col_numeric'
      ],
      'remote_cast': ['col_uuid', 'col_jsonb', 'col_inet', 'col_interval'],
      'remote_sql': 'select "id", "col_smallint", "col_integer", "col_real", "col_double", "col_boolean", "col_text", "col_varchar", "col_char", "col_bytea", "col_date", "col_timestamp", "col_timestamptz", "col_time", "col_json", "col_xml", "col_bit", "col_varbit", "col_numeric", cast("col_uuid" as text) as "col_uuid", cast("col_jsonb" as text) as "col_jsonb", cast("col_inet" as text) as "col_inet", cast("col_interval" as text) as "col_interval" from "public"."type_matrix"'
    }
  }) }}
{% endmacro %}

{% macro ir_fixture_alloydb_type_matrix() %}
  {{ return(ir_fixture_postgres_type_matrix(
    'alloydb_postgres',
    'analytics_alloydb',
    'projects/p/locations/us/connections/alloydb'
  )) }}
{% endmacro %}

{% macro ir_fixture_alloydb_orders() %}
  {{ return({
    'provider_family': 'postgres_federation',
    'schema': 'public',
    'table': 'orders',
    'connection': _ir_fixture_connection(
      'alloydb_postgres',
      'analytics_alloydb',
      'projects/p/locations/us/connections/alloydb',
      'safe',
      none
    ),
    'columns': [
      {'name': 'id', 'data_type': 'bigint'},
      {'name': 'user_uuid', 'data_type': 'uuid'},
      {'name': 'payload', 'data_type': 'jsonb'}
    ],
    'expected': {
      'body': 'projection',
      'pushdown': 'lost',
      'remote_sql': 'select "id", cast("user_uuid" as text) as "user_uuid", cast("payload" as text) as "payload" from "public"."orders"'
    }
  }) }}
{% endmacro %}
