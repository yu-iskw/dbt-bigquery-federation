with actual as (
    select
        id,
        name,
        email
    from {{ ref("stg_users") }}
),
expected as (
    select
        1 as id,
        '  Alice Smith  ' as name,
        ' ALICE@example.com ' as email
    union all
    select
        2 as id,
        'BOB' as name,
        'bob@example.com' as email
)

select
    actual.id,
    actual.name as actual_name,
    expected.name as expected_name,
    actual.email as actual_email,
    expected.email as expected_email
from actual
inner join expected using (id)
where actual.name <> expected.name
   or actual.email <> expected.email
