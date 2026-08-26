{% macro _federation_resolve_relation_schema(connection_cfg, schema=None) %}
  {# schema is required at the call site; empty string is Spanner's default schema. #}
  {{ return(schema) }}
{% endmacro %}

{% macro _federation_has_pin(connection, table, schema=None) %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection(connection) %}
  {% if not resolved.ok %}{{ return(false) }}{% endif %}
  {% set relation_schema = dbt_bigquery_federation._federation_resolve_relation_schema(resolved.connection, schema) %}
  {% if relation_schema is none %}{{ return(false) }}{% endif %}
  {% set cfg = dbt_bigquery_federation._federation_get_config() %}
  {% set tables = cfg.get('tables', {}) %}
  {% if tables is not mapping %}{{ return(false) }}{% endif %}
  {% set key = dbt_bigquery_federation._federation_pin_key(connection, relation_schema, table) %}
  {{ return(key in tables) }}
{% endmacro %}

{% macro _federation_resolve_metadata_mode(connection, table, schema=None, metadata_mode=None) %}
  {% if metadata_mode is none %}
    {% set cfg = dbt_bigquery_federation._federation_get_config() %}
    {% set metadata_cfg = cfg.get('metadata', {}) %}
    {% if metadata_cfg is mapping %}{% set mode = metadata_cfg.get('mode', 'auto') | string | lower | trim %}{% else %}{% set mode = 'auto' %}{% endif %}
  {% else %}
    {% set mode = metadata_mode | string | lower | trim %}
  {% endif %}
  {% if mode not in ['auto', 'live', 'pinned'] %}
    {{ return({'ok': false, 'error': 'metadata_mode must be auto, live, or pinned; got ' ~ mode, 'mode': none}) }}
  {% endif %}
  {% if mode == 'auto' %}
    {% if dbt_bigquery_federation._federation_has_pin(connection, table, schema) %}{{ return({'ok': true, 'error': none, 'mode': 'pinned'}) }}{% endif %}
    {{ return({'ok': true, 'error': none, 'mode': 'live'}) }}
  {% endif %}
  {{ return({'ok': true, 'error': none, 'mode': mode}) }}
{% endmacro %}

{% macro _federation_parse_stub(connection, table, schema=None) %}
  {% set resolved = dbt_bigquery_federation._federation_try_resolve_connection(connection) %}
  {% if not resolved.ok %}{{ return({'ok': false, 'error': resolved.error, 'sql': none}) }}{% endif %}
  {% set conn = resolved.connection %}
  {% set relation_schema = dbt_bigquery_federation._federation_resolve_relation_schema(conn, schema) %}
  {% if relation_schema is none %}
    {{ return({'ok': false, 'error': 'schema is required for ' ~ connection ~ '.' ~ table, 'sql': none}) }}
  {% endif %}
  {% set relation = dbt_bigquery_federation._federation_provider_render_remote_relation(conn.provider, relation_schema, table) %}
  {% set remote_sql = 'select * from ' ~ relation %}
  {{ return({'ok': true, 'error': none, 'sql': dbt_bigquery_federation._federation_render_external_query(conn.connection_id, remote_sql, none, conn.get('query_execution_priority'))}) }}
{% endmacro %}
