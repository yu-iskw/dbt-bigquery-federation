{% macro _spanner_google_federation_quote_identifier(identifier) %}
  {% if identifier is none or (identifier | string | trim) == '' %}
    {{ exceptions.raise_compiler_error('Spanner GoogleSQL identifier must be a non-empty string') }}
  {% endif %}
  {{ return('`' ~ (identifier | string | replace('`', '``')) ~ '`') }}
{% endmacro %}

{% macro _spanner_google_federation_quote_literal(value) %}
  {% set text = value | string %}
  {% set escaped = text
    | replace('\\', '\\\\')
    | replace("'", "\\'")
    | replace('\n', '\\n')
    | replace('\r', '\\r')
    | replace('\t', '\\t')
  %}
  {{ return("'" ~ escaped ~ "'") }}
{% endmacro %}

{% macro _spanner_google_federation_normalize_type_name(data_type) %}
  {% if data_type is none %}
    {{ return('') }}
  {% endif %}
  {% set normalized = dbt_bigquery_federation._federation_collapse_ws(data_type | string | upper) %}
  {# Strip length modifiers for STRING/BYTES; preserve ARRAY payload for classification. #}
  {% set normalized = modules.re.sub('^(STRING|BYTES)\\s*\\([^)]*\\)$', '\\1', normalized) %}
  {{ return(normalized) }}
{% endmacro %}

{% macro _spanner_google_federation_type_entry(data_type) %}
  {% set normalized = dbt_bigquery_federation._spanner_google_federation_normalize_type_name(data_type) %}
  {% set scalar = {
    'BOOL': {'target': 'BOOL', 'lossiness': 'exact'},
    'BYTES': {'target': 'BYTES', 'lossiness': 'exact'},
    'DATE': {'target': 'DATE', 'lossiness': 'exact'},
    'FLOAT64': {'target': 'FLOAT64', 'lossiness': 'exact'},
    'INT64': {'target': 'INT64', 'lossiness': 'exact'},
    'JSON': {'target': 'JSON', 'lossiness': 'exact'},
    'NUMERIC': {'target': 'NUMERIC', 'lossiness': 'range_risk'},
    'STRING': {'target': 'STRING', 'lossiness': 'exact'},
    'TIMESTAMP': {'target': 'TIMESTAMP', 'lossiness': 'precision_loss'}
  } %}
  {% if normalized in scalar %}
    {% set entry = scalar[normalized] %}
    {{ return({'kind': 'native', 'target': entry.target, 'lossiness': entry.lossiness, 'data_type': normalized, 'remote_type': 'STRING'}) }}
  {% endif %}
  {% if modules.re.match('^ARRAY<.+>$', normalized) is not none %}
    {% set inner = modules.re.sub('^ARRAY<(.+)>$', '\\1', normalized) %}
    {% if 'STRUCT' in inner %}
      {{ return({'kind': 'unsupported', 'target': none, 'lossiness': 'semantic_change', 'data_type': normalized, 'remote_type': none}) }}
    {% endif %}
    {{ return({'kind': 'native', 'target': 'ARRAY', 'lossiness': 'exact', 'data_type': normalized, 'remote_type': 'STRING'}) }}
  {% endif %}
  {% if modules.re.match('^STRUCT<.*>$', normalized) is not none or normalized == 'STRUCT' %}
    {{ return({'kind': 'unsupported', 'target': none, 'lossiness': 'semantic_change', 'data_type': normalized, 'remote_type': none}) }}
  {% endif %}
  {{ return({'kind': 'unknown', 'target': none, 'lossiness': 'unknown', 'data_type': normalized, 'remote_type': none}) }}
{% endmacro %}

{% macro _spanner_google_federation_render_remote_relation(schema, table) %}
  {# Spanner GoogleSQL supports named schemas; empty/default schema renders only the table. #}
  {% if schema is none or (schema | string | trim) == '' %}
    {{ return(dbt_bigquery_federation._spanner_google_federation_quote_identifier(table)) }}
  {% endif %}
  {{ return(dbt_bigquery_federation._spanner_google_federation_quote_identifier(schema) ~ '.' ~ dbt_bigquery_federation._spanner_google_federation_quote_identifier(table)) }}
{% endmacro %}

{% macro _spanner_google_federation_render_remote_cast(quoted_name, remote_type) %}
  {% if remote_type is none or (remote_type | upper) not in ['STRING', 'BYTES', 'INT64', 'FLOAT64', 'NUMERIC', 'BOOL', 'DATE', 'TIMESTAMP', 'JSON'] %}
    {{ exceptions.raise_compiler_error('Unsafe remote_type for Spanner GoogleSQL cast: ' ~ (remote_type | string)) }}
  {% endif %}
  {{ return('CAST(' ~ quoted_name ~ ' AS ' ~ (remote_type | upper) ~ ')') }}
{% endmacro %}
