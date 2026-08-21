{{ config(materialized='view') }}
/* stg_repayment_schedule - PROPOSED source. One row per expected installment; lump sum = 1 row. */
select distinct
    id                                  as schedule_id,
    loan_id,
    cast(installment_no as integer)     as installment_no,
    cast(due_date as date)              as due_date,
    cast(due_principal as {{ dbt.type_numeric() }}) as due_principal,
    cast(due_interest  as {{ dbt.type_numeric() }}) as due_interest,
    cast(due_amount    as {{ dbt.type_numeric() }}) as due_amount
from {{ ref('repayment_schedule') }}
