{{ config(materialized='view') }}
/*
  stg_insurance - one row per loan (latest). Source uses naive DATETIME (no tz):
  converted to UTC with a fixed UTC+7 offset (var source_utc_offset_hours).
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
    {{ dbt.dateadd('hour', -1 * var('source_utc_offset_hours'), 'cast(created_at as timestamp)') }}    as insured_at,
    {{ dbt.dateadd('hour', -1 * var('source_utc_offset_hours'), 'cast(updated_at as timestamp)') }}    as source_updated_at
from src
where rn = 1
