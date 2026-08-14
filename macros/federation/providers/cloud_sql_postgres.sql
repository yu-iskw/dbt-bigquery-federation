{% macro _cloud_sql_postgres_quote_identifier(identifier) %}
  {{ return(dbt_bigquery_federation._postgres_federation_quote_identifier(identifier)) }}
{% endmacro %}

{% macro _cloud_sql_postgres_quote_literal(value) %}
  {{ return(dbt_bigquery_federation._postgres_federation_quote_literal(value)) }}
{% endmacro %}

{% macro _cloud_sql_postgres_normalize_type_name(data_type) %}
  {{ return(dbt_bigquery_federation._postgres_federation_normalize_type_name(data_type)) }}
{% endmacro %}

{% macro _cloud_sql_postgres_type_map() %}
  {{ return(dbt_bigquery_federation._postgres_federation_type_map()) }}
{% endmacro %}

{% macro _cloud_sql_postgres_type_entry(data_type) %}
  {{ return(dbt_bigquery_federation._postgres_federation_type_entry(data_type)) }}
{% endmacro %}

{% macro _cloud_sql_postgres_render_remote_relation(schema, table) %}
  {{ return(dbt_bigquery_federation._postgres_federation_render_remote_relation(schema, table)) }}
{% endmacro %}

{% macro _cloud_sql_postgres_render_remote_cast(quoted_name, remote_type) %}
  {{ return(dbt_bigquery_federation._postgres_federation_render_remote_cast(quoted_name, remote_type)) }}
{% endmacro %}
