{% macro _federation_quote_bq_string(value) %}
  {% set text = value | string %}
  {{ return("'" ~ (text | replace('\\', '\\\\') | replace("'", "\\'")) ~ "'") }}
{% endmacro %}

{% macro _render_external_query(connection_id, remote_sql, decimal_option=None) %}
  {% if connection_id is none or remote_sql is none %}
    {{ exceptions.raise_compiler_error('EXTERNAL_QUERY renderer requires connection_id and remote SQL') }}
  {% endif %}
  {% set conn_lit = dbt_bigquery_federation._federation_quote_bq_string(connection_id) %}
  {% set query_lit = dbt_bigquery_federation._federation_quote_bq_string(remote_sql) %}
  {% if decimal_option %}
    {% set options_lit = dbt_bigquery_federation._federation_quote_bq_string(
      '{"default_type_for_decimal_columns":"' ~ (decimal_option | string) ~ '"}'
    ) %}
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
