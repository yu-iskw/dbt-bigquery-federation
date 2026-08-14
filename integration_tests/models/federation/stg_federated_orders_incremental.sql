{{ config(
    materialized='incremental',
    unique_key='id',
    on_schema_change='fail'
) }}

select *
from {{ dbt_bigquery_federation.federated_relation(
    connection='application_pg',
    schema='public',
    table='orders'
) }}
