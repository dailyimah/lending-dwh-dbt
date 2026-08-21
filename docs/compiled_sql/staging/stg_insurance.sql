
/*
  stg_insurance - one row per loan (latest). Source uses naive DATETIME (no tz):
  converted to UTC assuming reporting_timezone (see macros/dialect.sql).
*/
with src as (
    select *,
           row_number() over (partition by loan_id order by updated_at desc) as rn
    from "fazz_dwh"."main_raw"."insurance"
)
select
    id                                  as insurance_id,
    loan_id,
    cast(premium as numeric(28,6)) as premium_amount,
    vendor                              as insurance_vendor,
    lower(status)                       as insurance_status,
    timezone('UTC', timezone('Asia/Jakarta', cast(created_at as timestamp)))    as insured_at,
    timezone('UTC', timezone('Asia/Jakarta', cast(updated_at as timestamp)))    as source_updated_at
from src
where rn = 1