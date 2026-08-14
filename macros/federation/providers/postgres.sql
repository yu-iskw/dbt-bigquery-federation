{% macro _postgres_federation_quote_identifier(identifier) %}
  {% if identifier is none or (identifier | string | trim) == '' %}
    {{ exceptions.raise_compiler_error('PostgreSQL identifier must be a non-empty string') }}
  {% endif %}
  {{ return('"' ~ (identifier | string | replace('"', '""')) ~ '"') }}
{% endmacro %}

{% macro _postgres_federation_quote_literal(value) %}
  {{ return("'" ~ (value | string | replace("'", "''")) ~ "'") }}
{% endmacro %}

{% macro _postgres_federation_normalize_type_name(data_type) %}
  {% if data_type is none %}
    {{ return('') }}
  {% endif %}
  {% set normalized = dbt_bigquery_federation._federation_collapse_ws(data_type | string | lower) %}
  {% set aliases = {
    'int2': 'smallint',
    'int4': 'integer',
    'int': 'integer',
    'int8': 'bigint',
    'serial': 'integer',
    'bigserial': 'bigint',
    'smallserial': 'smallint',
    'float4': 'real',
    'float8': 'double precision',
    'bool': 'boolean',
    'varchar': 'character varying',
    'char': 'character',
    'timestamptz': 'timestamp with time zone',
    'timetz': 'time with time zone',
    'decimal': 'numeric',
    'timestamp': 'timestamp without time zone',
    'varbit': 'bit varying'
  } %}
  {# Preserve numeric typmods so invalid pin inputs fail rather than being silently normalized. #}
  {% if modules.re.match('^(numeric|decimal)\\s*\\(', normalized) is not none %}
    {{ return(normalized) }}
  {% endif %}
  {% set stripped = modules.re.sub('\\s*\\([^)]*\\)$', '', normalized) %}
  {% if stripped in aliases %}
    {{ return(aliases[stripped]) }}
  {% endif %}
  {{ return(stripped) }}
{% endmacro %}

{% macro _postgres_federation_type_map() %}
  {% set type_map = {
    'smallint': {'kind': 'native', 'target': 'INT64', 'lossiness': 'exact'},
    'integer': {'kind': 'native', 'target': 'INT64', 'lossiness': 'exact'},
    'bigint': {'kind': 'native', 'target': 'INT64', 'lossiness': 'exact'},
    'real': {'kind': 'native', 'target': 'FLOAT64', 'lossiness': 'exact'},
    'double precision': {'kind': 'native', 'target': 'FLOAT64', 'lossiness': 'exact'},
    'boolean': {'kind': 'native', 'target': 'BOOL', 'lossiness': 'exact'},
    'text': {'kind': 'native', 'target': 'STRING', 'lossiness': 'exact'},
    'character varying': {'kind': 'native', 'target': 'STRING', 'lossiness': 'exact'},
    'character': {'kind': 'native', 'target': 'STRING', 'lossiness': 'exact'},
    'name': {'kind': 'native', 'target': 'STRING', 'lossiness': 'exact'},
    'bytea': {'kind': 'native', 'target': 'BYTES', 'lossiness': 'exact'},
    'date': {'kind': 'native', 'target': 'DATE', 'lossiness': 'exact'},
    'timestamp without time zone': {'kind': 'native', 'target': 'DATETIME', 'lossiness': 'exact'},
    'timestamp with time zone': {'kind': 'native', 'target': 'TIMESTAMP', 'lossiness': 'exact'},
    'time': {'kind': 'native', 'target': 'TIME', 'lossiness': 'exact'},
    'time without time zone': {'kind': 'native', 'target': 'TIME', 'lossiness': 'exact'},
    'json': {'kind': 'native', 'target': 'STRING', 'lossiness': 'representation_change'},
    'xml': {'kind': 'native', 'target': 'STRING', 'lossiness': 'representation_change'},
    'bit': {'kind': 'native', 'target': 'BYTES', 'lossiness': 'exact'},
    'bit varying': {'kind': 'native', 'target': 'BYTES', 'lossiness': 'exact'},
    'numeric': {'kind': 'decimal', 'target': 'NUMERIC', 'lossiness': 'exact'}
  } %}
  {% set unsupported = {
    'kind': 'unsupported',
    'target': 'STRING',
    'lossiness': 'representation_change',
    'remote_type': 'text'
  } %}
  {% do type_map.update({
    'uuid': unsupported,
    'jsonb': unsupported,
    'money': unsupported,
    'inet': unsupported,
    'cidr': unsupported,
    'macaddr': unsupported,
    'macaddr8': unsupported,
    'interval': unsupported,
    'time with time zone': unsupported,
    'point': unsupported,
    'line': unsupported,
    'lseg': unsupported,
    'box': unsupported,
    'path': unsupported,
    'polygon': unsupported,
    'circle': unsupported,
    'pg_lsn': unsupported,
    'tsquery': unsupported,
    'tsvector': unsupported,
    'txid_snapshot': unsupported
  }) %}
  {{ return(type_map) }}
{% endmacro %}

{% macro _postgres_federation_type_entry(data_type) %}
  {% set normalized = dbt_bigquery_federation._postgres_federation_normalize_type_name(data_type) %}
  {% set type_map = dbt_bigquery_federation._postgres_federation_type_map() %}
  {% if normalized in type_map %}
    {% set entry = type_map[normalized] %}
    {{ return({
      'kind': entry.kind,
      'target': entry.target,
      'lossiness': entry.lossiness,
      'remote_type': entry.get('remote_type', 'text'),
      'data_type': normalized
    }) }}
  {% endif %}
  {{ return({'kind': 'unknown', 'target': none, 'lossiness': 'unknown', 'data_type': normalized, 'remote_type': 'text'}) }}
{% endmacro %}

{% macro _postgres_federation_render_remote_relation(schema, table) %}
  {{ return(dbt_bigquery_federation._postgres_federation_quote_identifier(schema) ~ '.' ~ dbt_bigquery_federation._postgres_federation_quote_identifier(table)) }}
{% endmacro %}

{% macro _postgres_federation_render_remote_cast(quoted_name, remote_type) %}
  {% if not dbt_bigquery_federation._federation_validate_remote_type(remote_type) %}
    {{ exceptions.raise_compiler_error('Unsafe remote_type for PostgreSQL cast: ' ~ (remote_type | string)) }}
  {% endif %}
  {{ return('cast(' ~ quoted_name ~ ' as ' ~ (remote_type | string | lower | trim) ~ ')') }}
{% endmacro %}
