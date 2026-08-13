{% macro _render_external_query(connection_id, remote_sql, decimal_option=None) %}
  {% if connection_id is none or remote_sql is none %}
    {{ exceptions.raise_compiler_error('EXTERNAL_QUERY renderer requires connection_id and remote SQL') }}
  {% endif %}
  {% set conn_lit = "'" ~ (connection_id | string | replace("'", "\\'")) ~ "'" %}
  {% set sql_text = remote_sql | string %}
  {% if "'''" in sql_text %}
    {{ exceptions.raise_compiler_error('Remote SQL must not contain triple single quotes') }}
  {% endif %}
  {% set query_lit = "'''" ~ sql_text ~ "'''" %}
  {% if decimal_option %}
    {% set options_lit = '\'{"default_type_for_decimal_columns":"' ~ (decimal_option | string) ~ '"}\'' %}
    {{ return('EXTERNAL_QUERY(' ~ conn_lit ~ ', ' ~ query_lit ~ ', ' ~ options_lit ~ ')') }}
  {% endif %}
  {{ return('EXTERNAL_QUERY(' ~ conn_lit ~ ', ' ~ query_lit ~ ')') }}
{% endmacro %}

{% macro _federation_collapse_ws(value) %}
  {% if value is none %}
    {{ return('') }}
  {% endif %}
  {{ return(modules.re.sub('\\s+', ' ', value | string) | trim) }}
{% endmacro %}
