{% macro _federation_provider_quote_identifier(provider, identifier) %}
  {% set descriptor = dbt_bigquery_federation._federation_provider_descriptor(provider) %}
  {% if descriptor is none %}
    {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
  {% endif %}
  {% if descriptor.dialect == 'postgres' %}
    {{ return(dbt_bigquery_federation._postgres_federation_quote_identifier(identifier)) }}
  {% elif descriptor.dialect == 'spanner_google_sql' %}
    {{ return(dbt_bigquery_federation._spanner_google_federation_quote_identifier(identifier)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation dialect: ' ~ descriptor.dialect) }}
{% endmacro %}

{% macro _federation_provider_quote_literal(provider, value) %}
  {% set descriptor = dbt_bigquery_federation._federation_provider_descriptor(provider) %}
  {% if descriptor is none %}
    {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
  {% endif %}
  {% if descriptor.dialect == 'postgres' %}
    {{ return(dbt_bigquery_federation._postgres_federation_quote_literal(value)) }}
  {% elif descriptor.dialect == 'spanner_google_sql' %}
    {{ return(dbt_bigquery_federation._spanner_google_federation_quote_literal(value)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation dialect: ' ~ descriptor.dialect) }}
{% endmacro %}

{% macro _federation_provider_normalize_type_name(provider, data_type) %}
  {% set descriptor = dbt_bigquery_federation._federation_provider_descriptor(provider) %}
  {% if descriptor is none %}
    {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
  {% endif %}
  {% if descriptor.type_profile == 'postgres_federation' %}
    {{ return(dbt_bigquery_federation._postgres_federation_normalize_type_name(data_type)) }}
  {% elif descriptor.type_profile == 'spanner_google_federation' %}
    {{ return(dbt_bigquery_federation._spanner_google_federation_normalize_type_name(data_type)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation type profile: ' ~ descriptor.type_profile) }}
{% endmacro %}

{% macro _federation_provider_type_entry(provider, data_type) %}
  {% set descriptor = dbt_bigquery_federation._federation_provider_descriptor(provider) %}
  {% if descriptor is none %}
    {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
  {% endif %}
  {% if descriptor.type_profile == 'postgres_federation' %}
    {{ return(dbt_bigquery_federation._postgres_federation_type_entry(data_type)) }}
  {% elif descriptor.type_profile == 'spanner_google_federation' %}
    {{ return(dbt_bigquery_federation._spanner_google_federation_type_entry(data_type)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation type profile: ' ~ descriptor.type_profile) }}
{% endmacro %}

{% macro _federation_provider_render_remote_relation(provider, schema, table) %}
  {% set descriptor = dbt_bigquery_federation._federation_provider_descriptor(provider) %}
  {% if descriptor is none %}
    {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
  {% endif %}
  {% if descriptor.dialect == 'postgres' %}
    {{ return(dbt_bigquery_federation._postgres_federation_render_remote_relation(schema, table)) }}
  {% elif descriptor.dialect == 'spanner_google_sql' %}
    {{ return(dbt_bigquery_federation._spanner_google_federation_render_remote_relation(schema, table)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation dialect: ' ~ descriptor.dialect) }}
{% endmacro %}

{% macro _federation_provider_render_remote_cast(provider, quoted_name, remote_type) %}
  {% set descriptor = dbt_bigquery_federation._federation_provider_descriptor(provider) %}
  {% if descriptor is none %}
    {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
  {% endif %}
  {% if descriptor.dialect == 'postgres' %}
    {{ return(dbt_bigquery_federation._postgres_federation_render_remote_cast(quoted_name, remote_type)) }}
  {% elif descriptor.dialect == 'spanner_google_sql' %}
    {{ return(dbt_bigquery_federation._spanner_google_federation_render_remote_cast(quoted_name, remote_type)) }}
  {% endif %}
  {{ exceptions.raise_compiler_error('Unsupported federation dialect: ' ~ descriptor.dialect) }}
{% endmacro %}
