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
  {% set matched = modules.re.match('^projects/[^/]+/locations/[^/]+/connections/[^/]+$', connection_id | string) %}
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
  {% if provider != 'cloud_sql_postgres' %}
    {{ return({
      'ok': false,
      'error': 'Unsupported provider ' ~ (provider | string) ~ ' for ' ~ connection_name ~ '. v0.1 supports cloud_sql_postgres only.',
      'connection': none
    }) }}
  {% endif %}
  {% set connection_id = conn.get('connection_id') %}
  {% if not dbt_bigquery_federation._federation_connection_id_is_valid(connection_id) %}
    {{ return({
      'ok': false,
      'error': 'connection_id for ' ~ connection_name ~ ' must match projects/PROJECT/locations/LOCATION/connections/NAME',
      'connection': none
    }) }}
  {% endif %}
  {% set defaults = conn.get('defaults', {}) %}
  {% if defaults is not mapping %}
    {{ return({'ok': false, 'error': 'Connection ' ~ connection_name ~ ' defaults must be a mapping', 'connection': none}) }}
  {% endif %}
  {% set types = conn.get('types', {}) %}
  {% if types is not mapping %}
    {{ return({'ok': false, 'error': 'Connection ' ~ connection_name ~ ' types must be a mapping', 'connection': none}) }}
  {% endif %}
  {{ return({
    'ok': true,
    'error': none,
    'connection': {
      'alias': connection_name,
      'connection_id': connection_id | string,
      'provider': provider,
      'default_schema': defaults.get('schema'),
      'policy': types.get('policy', 'safe')
    }
  }) }}
{% endmacro %}

{% macro _federation_package_type_overrides() %}
  {% set cfg = dbt_bigquery_federation._federation_get_config() %}
  {% set overrides = cfg.get('type_overrides', {}) %}
  {% if overrides is not mapping %}
    {{ exceptions.raise_compiler_error('vars.dbt_bigquery_federation.type_overrides must be a mapping') }}
  {% endif %}
  {{ return(overrides) }}
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
