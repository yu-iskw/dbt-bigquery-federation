{% macro _federation_get_config() %}
  {% set cfg = var('dbt_bigquery_federation', {}) %}
  {% if cfg is not mapping %}
    {{ exceptions.raise_compiler_error('vars.dbt_bigquery_federation must be a mapping') }}
  {% endif %}
  {{ return(cfg) }}
{% endmacro %}

{% macro _federation_connection_id_is_valid(connection_id) %}
  {% if connection_id is none %}
    {{ return(false) }}
  {% endif %}
  {% set matched = modules.re.match('^projects/[^/\\s]+/locations/[^/\\s]+/connections/[^/\\s]+$', connection_id | string | trim) %}
  {{ return(matched is not none) }}
{% endmacro %}

{% macro _federation_try_resolve_connection(connection_name) %}
  {% set cfg = dbt_bigquery_federation._federation_get_config() %}
  {% set connections = cfg.get('connections', {}) %}
  {% if connections is not mapping %}
    {{ return({'ok': false, 'error': 'vars.dbt_bigquery_federation.connections must be a mapping', 'connection': none}) }}
  {% endif %}
  {% if connection_name not in connections %}
    {{ return({'ok': false, 'error': 'Unknown federation connection alias: ' ~ connection_name, 'connection': none}) }}
  {% endif %}
  {% set conn = connections[connection_name] %}
  {% if conn is not mapping %}
    {{ return({'ok': false, 'error': 'Connection ' ~ connection_name ~ ' must be a mapping', 'connection': none}) }}
  {% endif %}
  {% set provider = conn.get('provider') %}
  {% set descriptor = dbt_bigquery_federation._federation_provider_descriptor(provider) %}
  {% if descriptor is none %}
    {{ return({'ok': false, 'error': 'Unsupported federation provider ' ~ (provider | string) ~ ' for ' ~ connection_name, 'connection': none}) }}
  {% endif %}
  {% set cid = namespace(value=conn.get('connection_id')) %}
  {% if cid.value is not none %}{% set cid.value = cid.value | string | trim %}{% endif %}
  {% if not dbt_bigquery_federation._federation_connection_id_is_valid(cid.value) %}
    {{ return({'ok': false, 'error': 'connection_id for ' ~ connection_name ~ ' must match projects/PROJECT/locations/LOCATION/connections/NAME', 'connection': none}) }}
  {% endif %}
  {% set defaults = conn.get('defaults', {}) %}
  {% if defaults is not mapping %}
    {{ return({'ok': false, 'error': 'Connection ' ~ connection_name ~ ' defaults must be a mapping', 'connection': none}) }}
  {% endif %}
  {% set types = conn.get('types', {}) %}
  {% if types is not mapping %}
    {{ return({'ok': false, 'error': 'Connection ' ~ connection_name ~ ' types must be a mapping', 'connection': none}) }}
  {% endif %}
  {% set options = conn.get('options', {}) %}
  {% if options is not mapping %}
    {{ return({'ok': false, 'error': 'Connection ' ~ connection_name ~ ' options must be a mapping', 'connection': none}) }}
  {% endif %}
  {% set priority = options.get('query_execution_priority') %}
  {% if priority is not none %}
    {% set priority = priority | string | lower | trim %}
    {% if not descriptor.capabilities.get('query_execution_priority', false) %}
      {{ return({'ok': false, 'error': 'Provider ' ~ provider ~ ' does not support query_execution_priority', 'connection': none}) }}
    {% endif %}
    {% if priority not in ['high', 'medium', 'low'] %}
      {{ return({'ok': false, 'error': 'query_execution_priority must be high, medium, or low', 'connection': none}) }}
    {% endif %}
  {% endif %}
  {{ return({'ok': true, 'error': none, 'connection': {
    'alias': connection_name,
    'connection_id': cid.value | string,
    'provider': provider,
    'connection_kind': descriptor.connection_kind,
    'dialect': descriptor.dialect,
    'metadata_profile': descriptor.metadata_profile,
    'type_profile': descriptor.type_profile,
    'capabilities': descriptor.capabilities,
    'default_schema': defaults.get('schema'),
    'policy': types.get('policy', 'safe'),
    'query_execution_priority': priority
  }}) }}
{% endmacro %}

{% macro _federation_package_type_overrides(provider=None) %}
  {% set cfg = dbt_bigquery_federation._federation_get_config() %}
  {% set overrides = cfg.get('type_overrides', {}) %}
  {% if overrides is not mapping %}
    {{ exceptions.raise_compiler_error('vars.dbt_bigquery_federation.type_overrides must be a mapping') }}
  {% endif %}
  {% set normalized = namespace(map={}) %}
  {% for key, value in overrides.items() %}
    {% set normalized_key = dbt_bigquery_federation._federation_provider_normalize_type_name(provider or 'cloud_sql_postgres', key) %}
    {% do normalized.map.update({normalized_key: value}) %}
  {% endfor %}
  {{ return(normalized.map) }}
{% endmacro %}

{% macro _federation_resolve_policy(connection_cfg, type_policy) %}
  {% if type_policy is not none %}
    {% set policy = type_policy | string | lower | trim %}
  {% else %}
    {% set policy = (connection_cfg.policy | default('safe') | string | lower | trim) %}
  {% endif %}
  {% if policy not in ['safe', 'strict'] %}
    {{ return({'ok': false, 'error': 'type_policy must be safe or strict, got ' ~ policy, 'policy': none}) }}
  {% endif %}
  {{ return({'ok': true, 'error': none, 'policy': policy}) }}
{% endmacro %}
