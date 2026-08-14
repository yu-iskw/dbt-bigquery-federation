{{ config(materialized="view") }}

select
  id,
  raw_name as name,
  raw_email as email
from {{ ref("raw_users") }}
