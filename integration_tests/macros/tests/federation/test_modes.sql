{% macro test_federated_relation_pin_path_is_stable() %}
  {% set sql_a = dbt_bigquery_federation.federated_relation('application_pg', 'orders', 'public') %}
  {% set sql_b = dbt_bigquery_federation.federated_relation(
    'application_pg', 'orders', 'public', none, none, 'pinned'
  ) %}
  {% do dbt_unittest.assert_equals(
    dbt_bigquery_federation._federation_collapse_ws(sql_a),
    dbt_bigquery_federation._federation_collapse_ws(sql_b)
  ) %}
  {% do dbt_unittest.assert_equals('select * from' in sql_a, false) %}
  {% do dbt_unittest.assert_equals('"id"' in sql_a, true) %}
{% endmacro %}
