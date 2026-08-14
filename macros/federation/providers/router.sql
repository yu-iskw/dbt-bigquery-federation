{% macro _federation_provider_quote_identifier(provider, identifier) %}
  {% if provider == 'cloud_sql_postgres' %}
    {{ return(dbt_bigquery_federation._cloud_sql_postgres_quote_identifier(identifier)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
{% endmacro %}

{% macro _federation_provider_quote_literal(provider, value) %}
  {% if provider == 'cloud_sql_postgres' %}
    {{ return(dbt_bigquery_federation._cloud_sql_postgres_quote_literal(value)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
{% endmacro %}

{% macro _federation_provider_normalize_type_name(provider, data_type) %}
  {% if provider == 'cloud_sql_postgres' %}
    {{ return(dbt_bigquery_federation._cloud_sql_postgres_normalize_type_name(data_type)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
{% endmacro %}

{% macro _federation_provider_type_entry(provider, data_type) %}
  {% if provider == 'cloud_sql_postgres' %}
    {{ return(dbt_bigquery_federation._cloud_sql_postgres_type_entry(data_type)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
{% endmacro %}

{% macro _federation_provider_render_remote_relation(provider, schema, table) %}
  {% if provider == 'cloud_sql_postgres' %}
    {{ return(dbt_bigquery_federation._cloud_sql_postgres_render_remote_relation(schema, table)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
{% endmacro %}

{% macro _federation_provider_render_remote_cast(provider, quoted_name, remote_type) %}
  {% if provider == 'cloud_sql_postgres' %}
    {{ return(dbt_bigquery_federation._cloud_sql_postgres_render_remote_cast(quoted_name, remote_type)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
{% endmacro %}
