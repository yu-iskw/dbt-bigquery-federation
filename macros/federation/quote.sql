{% macro _federation_identifier_is_safe_unquoted(identifier) %}
  {% if identifier is none %}
    {{ return(false) }}
  {% endif %}
  {{ return(modules.re.match('^[a-z_][a-z0-9_]*$', identifier | string) is not none) }}
{% endmacro %}
