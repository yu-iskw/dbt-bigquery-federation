{% macro _federation_pin_key(connection, schema, table) %}
  {{ return((connection | string) ~ '.' ~ (schema | string) ~ '.' ~ (table | string)) }}
{% endmacro %}

{% macro _federation_try_load_pin(connection, table, schema=None) %}
  {% set resolved = _federation_try_resolve_connection(connection) %}
  {% if not resolved.ok %}
    {{ return({'ok': false, 'error': resolved.error, 'pin': none, 'connection': none}) }}
  {% endif %}
  {% set conn = resolved.connection %}
  {% set relation_schema = schema %}
  {% if relation_schema is none %}
    {% set relation_schema = conn.default_schema %}
  {% endif %}
  {% if relation_schema is none %}
    {{ return({
      'ok': false,
      'error': 'schema is required for ' ~ connection ~ '.' ~ table ~ ' (no connection defaults.schema)',
      'pin': none,
      'connection': none
    }) }}
  {% endif %}
  {% set cfg = _federation_get_config() %}
  {% set tables = cfg.get('tables', {}) %}
  {% if tables is not mapping %}
    {{ return({'ok': false, 'error': 'vars.dbt_bigquery_federation.tables must be a mapping', 'pin': none, 'connection': none}) }}
  {% endif %}
  {% set key = _federation_pin_key(connection, relation_schema, table) %}
  {% if key not in tables %}
    {{ return({
      'ok': false,
      'error': 'Missing federation pin for ' ~ key ~ '. Declare columns under vars.dbt_bigquery_federation.tables.',
      'pin': none,
      'connection': none
    }) }}
  {% endif %}
  {% set pin = tables[key] %}
  {% if pin is not mapping %}
    {{ return({'ok': false, 'error': 'Pin ' ~ key ~ ' must be a mapping with columns', 'pin': none, 'connection': none}) }}
  {% endif %}
  {% set columns = pin.get('columns') %}
  {% if columns is not sequence or columns is string %}
    {{ return({'ok': false, 'error': 'Pin ' ~ key ~ ' columns must be a list', 'pin': none, 'connection': none}) }}
  {% endif %}
  {{ return({
    'ok': true,
    'error': none,
    'connection': conn,
    'pin': {
      'key': key,
      'schema': relation_schema,
      'table': table,
      'columns': columns
    }
  }) }}
{% endmacro %}
