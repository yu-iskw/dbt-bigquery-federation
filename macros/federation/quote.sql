{% macro _federation_quote_identifier(provider, identifier) %}
  {{ return(dbt_bigquery_federation._federation_provider_quote_identifier(provider, identifier)) }}
{% endmacro %}

{% macro _federation_quote_literal(provider, value) %}
  {{ return(dbt_bigquery_federation._federation_provider_quote_literal(provider, value)) }}
{% endmacro %}

{% macro _federation_identifier_is_safe_unquoted(identifier) %}
  {% if identifier is none %}
    {{ return(false) }}
  {% endif %}
  {% set matched = modules.re.match('^[a-z_][a-z0-9_]*$', identifier | string) %}
  {{ return(matched is not none) }}
{% endmacro %}
