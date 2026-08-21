{{ config(materialized='view') }}
/* stg_fund - one row per lender funding commitment to a loan. */
select distinct
    id                                  as fund_id,
    loan_id,
    lender_account_id                   as lender_customer_id,
    cast(nominal    as {{ dbt.type_numeric() }}) as committed_amount,
    cast(fund_ratio as {{ dbt.type_numeric() }}) as fund_ratio,
    lower(status)                       as fund_status,
    cast(created_at as timestamp)       as funded_at,
    cast(updated_at as timestamp)       as source_updated_at
from {{ ref('fund') }}
