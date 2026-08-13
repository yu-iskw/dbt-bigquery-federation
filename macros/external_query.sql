{% macro external_query(connection, sql) -%}
  {{ return(adapter.dispatch('external_query', 'dbt_bigquery_federation')(connection, sql)) }}
{%- endmacro %}

{% macro default__external_query(connection, sql) -%}
  {% set resolved = _federation_try_resolve_connection(connection) %}
  {% if not resolved.ok %}
    {{ exceptions.raise_compiler_error(resolved.error) }}
  {% endif %}
  {{ return(_render_external_query(resolved.connection.connection_id, sql, none)) }}
{%- endmacro %}
