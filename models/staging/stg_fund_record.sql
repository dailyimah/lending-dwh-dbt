{{ config(materialized='view') }}
/* stg_fund_record - settlement/signing records of a funding commitment. */
select distinct
    id                                  as fund_record_id,
    funding_id                          as fund_id,
    cast(amount as {{ dbt.type_numeric() }}) as amount,
    cast(is_settled as boolean)         as is_settled,
    cast(is_signed  as boolean)         as is_signed,
    cast(created_at as timestamp)       as recorded_at,
    cast(updated_at as timestamp)       as source_updated_at
from {{ ref('fund_record') }}
