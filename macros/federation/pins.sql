{% macro _federation_pin_key(connection, schema, table) %}
  {{ return((connection | string) ~ '.' ~ (schema | string) ~ '.' ~ (table | string)) }}
{% endmacro %}

{% macro _federation_resolve_relation_schema(connection_cfg, schema=None) %}
  {# schema is required at the call site; empty string is Spanner's default schema. #}
  {{ return(schema) }}
{% endmacro %}

{% macro _federation_try_load_pin(connection, table, schema=None) %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection(connection) %}
  {% if not resolved.ok %}
    {{ return({'ok': false, 'error': resolved.error, 'pin': none, 'connection': none}) }}
  {% endif %}
  {% set conn = resolved.connection %}
  {% set relation_schema = dbt_bigquery_federation._federation_resolve_relation_schema(conn, schema) %}
  {% if relation_schema is none %}
    {{ return({
      'ok': false,
      'error': 'schema is required for ' ~ connection ~ '.' ~ table,
      'pin': none,
      'connection': none
    }) }}
  {% endif %}
  {% set cfg = dbt_bigquery_federation._federation_get_config() %}
  {% set tables = cfg.get('tables', {}) %}
  {% if tables is not mapping %}
    {{ return({'ok': false, 'error': 'vars.dbt_bigquery_federation.tables must be a mapping', 'pin': none, 'connection': none}) }}
  {% endif %}
  {% set key = dbt_bigquery_federation._federation_pin_key(connection, relation_schema, table) %}
  {% if key not in tables %}
    {{ return({
      'ok': false,
      'error': 'Missing federation pin for connection ' ~ connection ~ ' key ' ~ key ~ '. Declare columns under vars.dbt_bigquery_federation.tables (or root vars.yml on dbt 1.12+), or run-operation federation_generate_pin and commit the printed YAML.',
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
  {% if columns | length == 0 %}
    {{ return({'ok': false, 'error': 'Pin ' ~ key ~ ' columns must not be empty', 'pin': none, 'connection': none}) }}
  {% endif %}
  {% set seen = namespace(names=[]) %}
  {% for col in columns %}
    {% if col is not mapping %}
      {{ return({'ok': false, 'error': 'Pin ' ~ key ~ ' column entries must be mappings', 'pin': none, 'connection': none}) }}
    {% endif %}
    {% set raw_name = col.get('name') %}
    {% if raw_name is none %}
      {{ return({'ok': false, 'error': 'Pin ' ~ key ~ ' has a column with an empty name', 'pin': none, 'connection': none}) }}
    {% endif %}
    {% set col_name = raw_name | string | trim %}
    {% if not col_name %}
      {{ return({'ok': false, 'error': 'Pin ' ~ key ~ ' has a column with an empty name', 'pin': none, 'connection': none}) }}
    {% endif %}
    {% if col_name in seen.names %}
      {{ return({'ok': false, 'error': 'Pin ' ~ key ~ ' has duplicate column name ' ~ col_name, 'pin': none, 'connection': none}) }}
    {% endif %}
    {% do seen.names.append(col_name) %}
    {% do col.update({'name': col_name}) %}
    {% for field in ['precision', 'scale', 'character_maximum_length'] %}
      {% set raw = col.get(field) %}
      {% if raw is not none and modules.re.match('^[0-9]+$', raw | string) is none %}
        {{ return({
          'ok': false,
          'error': 'Pin ' ~ key ~ ' column ' ~ col_name ~ ' ' ~ field ~ ' must be a non-negative integer',
          'pin': none,
          'connection': none
        }) }}
      {% endif %}
    {% endfor %}
  {% endfor %}
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
