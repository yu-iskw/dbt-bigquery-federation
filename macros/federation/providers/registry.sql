{% macro _federation_provider_descriptor(provider) %}
  {% set postgres_caps = {
    'schema_discovery': true,
    'select_star_pushdown': true,
    'decimal_default_option': true,
    'query_execution_priority': false,
    'arrays': false,
    'structs': false
  } %}
  {% set providers = {
    'cloud_sql_postgres': {
      'connection_kind': 'cloud_sql',
      'dialect': 'postgres',
      'metadata_profile': 'postgres_information_schema',
      'type_profile': 'postgres_federation',
      'capabilities': postgres_caps
    },
    'alloydb_postgres': {
      'connection_kind': 'alloydb',
      'dialect': 'postgres',
      'metadata_profile': 'postgres_information_schema',
      'type_profile': 'postgres_federation',
      'capabilities': postgres_caps
    },
    'spanner_google_sql': {
      'connection_kind': 'spanner',
      'dialect': 'spanner_google_sql',
      'metadata_profile': 'spanner_google_information_schema',
      'type_profile': 'spanner_google_federation',
      'capabilities': {
        'schema_discovery': true,
        'select_star_pushdown': true,
        'decimal_default_option': false,
        'query_execution_priority': true,
        'arrays': true,
        'structs': false
      }
    }
  } %}
  {% if provider not in providers %}
    {{ return(none) }}
  {% endif %}
  {{ return(providers[provider]) }}
{% endmacro %}

{% macro _federation_provider_is_supported(provider) %}
  {{ return(dbt_bigquery_federation._federation_provider_descriptor(provider) is not none) }}
{% endmacro %}

{% macro _federation_provider_capability(provider, capability, default=false) %}
  {% set descriptor = dbt_bigquery_federation._federation_provider_descriptor(provider) %}
  {% if descriptor is none %}
    {{ exceptions.raise_compiler_error('Unsupported federation provider: ' ~ (provider | string)) }}
  {% endif %}
  {{ return(descriptor.capabilities.get(capability, default)) }}
{% endmacro %}
