{{ config(materialized="view") }}

select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
