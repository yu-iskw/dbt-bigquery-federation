{% macro _cloud_sql_postgres_quote_identifier(identifier) %}
  {% if identifier is none or (identifier | string | trim) == '' %}
    {{ exceptions.raise_compiler_error('PostgreSQL identifier must be a non-empty string') }}
  {% endif %}
  {% set ident = identifier | string %}
  {% if dbt_bigquery_federation._federation_identifier_is_safe_unquoted(ident) %}
    {{ return(ident) }}
  {% endif %}
  {{ return('"' ~ (ident | replace('"', '""')) ~ '"') }}
{% endmacro %}

{% macro _cloud_sql_postgres_quote_literal(value) %}
  {{ return("'" ~ (value | string | replace("'", "''")) ~ "'") }}
{% endmacro %}

{% macro _cloud_sql_postgres_normalize_type_name(data_type) %}
  {% if data_type is none %}
    {{ return('') }}
  {% endif %}
  {% set normalized = modules.re.sub('\\s+', ' ', data_type | string | lower) | trim %}
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
    'timestamp': 'timestamp without time zone'
  } %}
  {% if normalized in aliases %}
    {{ return(aliases[normalized]) }}
  {% endif %}
  {{ return(normalized) }}
{% endmacro %}

{% macro _cloud_sql_postgres_type_map() %}
  {{ return({
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
    'numeric': {'kind': 'decimal', 'target': 'NUMERIC', 'lossiness': 'exact'},
    'uuid': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'jsonb': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'money': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'inet': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'cidr': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'macaddr': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'macaddr8': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'interval': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'time with time zone': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'point': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'line': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'lseg': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'box': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'path': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'polygon': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'},
    'circle': {'kind': 'unsupported', 'target': 'STRING', 'lossiness': 'representation_change', 'remote_type': 'text'}
  }) }}
{% endmacro %}

{% macro _cloud_sql_postgres_type_entry(data_type) %}
  {% set normalized = dbt_bigquery_federation._cloud_sql_postgres_normalize_type_name(data_type) %}
  {% set type_map = dbt_bigquery_federation._cloud_sql_postgres_type_map() %}
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

{% macro _cloud_sql_postgres_render_remote_relation(schema, table) %}
  {{ return(dbt_bigquery_federation._cloud_sql_postgres_quote_identifier(schema) ~ '.' ~ dbt_bigquery_federation._cloud_sql_postgres_quote_identifier(table)) }}
{% endmacro %}

{% macro _cloud_sql_postgres_render_remote_cast(quoted_name, remote_type) %}
  {{ return('cast(' ~ quoted_name ~ ' as ' ~ remote_type ~ ')') }}
{% endmacro %}
