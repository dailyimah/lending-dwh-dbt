{{ config(materialized='view') }}
/*
  stg_loan - one row per loan (latest version).
  Fixes: movement_status_id INTEGER -> STRING so it can join movement_status.movement_id.
*/
with src as (
    select *,
           row_number() over (partition by loan_id order by updated_at desc) as rn
    from {{ ref('loan') }}
)
select
    loan_id,
    borrower_account_id                         as borrower_customer_id,
    loan_type_id,
    tenor                                       as tenor_months,
    cast(nominal_request as {{ dbt.type_numeric() }})  as nominal_request,
    cast(nominal_loan    as {{ dbt.type_numeric() }})  as nominal_loan,
    upper(grade)                                as grade,
    lower(repayment_mode)                       as repayment_mode,
    cast(movement_status_id as {{ dbt.type_string() }}) as source_movement_id,    -- type fix (INTEGER -> STRING)
    cast(created_at as timestamp)               as requested_at,
    cast(updated_at as timestamp)               as source_updated_at
from src
where rn = 1
