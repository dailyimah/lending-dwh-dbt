{{ config(materialized='view') }}
/*
  stg_insurance - one row per loan (latest). Source uses naive DATETIME (no tz):
  converted to UTC assuming reporting_timezone (see macros/dialect.sql).
*/
with src as (
    select *,
           row_number() over (partition by loan_id order by updated_at desc) as rn
    from {{ ref('insurance') }}
)
select
    id                                  as insurance_id,
    loan_id,
    cast(premium as {{ dbt.type_numeric() }}) as premium_amount,
    vendor                              as insurance_vendor,
    lower(status)                       as insurance_status,
    {{ local_to_utc('created_at') }}    as insured_at,
    {{ local_to_utc('updated_at') }}    as source_updated_at
from src
where rn = 1
