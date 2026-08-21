
/*
  stg_individual - individual customers, ALL versions kept (SCD2 input).
  - naive DATETIME -> UTC (assumed reporting_timezone)
  - drops "no-change" re-touches: rows identical in content that differ only by updated_at
  - shaped to the unified customer contract (company-only columns NULL)
*/
with typed as (
    select
        id                                  as customer_id,
        cast('individual' as TEXT) as entity_type,
        trim(name)                          as customer_name,
        lower(trim(email))                  as email,
        phone_number,
        country_id, province_id, city_id, district_id,
        cast(is_borrower as boolean)        as is_borrower,
        cast(is_lender  as boolean)         as is_lender,
        upper(identity_card_type)           as identity_card_type,
        cast(null as date)                  as founded_date,
        cast(null as TEXT) as pic_name,
        cast(null as TEXT) as nib_number,
        timezone('UTC', timezone('Asia/Jakarta', cast(created_at as timestamp)))    as source_created_at,
        timezone('UTC', timezone('Asia/Jakarta', cast(updated_at as timestamp)))    as source_updated_at
    from "fazz_dwh"."main_raw"."individual"
),
dedup as (
    select *,
           row_number() over (
               partition by customer_id, customer_name, email, phone_number, country_id, province_id, city_id, district_id, is_borrower, is_lender, identity_card_type, founded_date, pic_name, nib_number
               order by source_updated_at
           ) as rn
    from typed
)
select customer_id, entity_type, customer_name, email, phone_number, country_id, province_id, city_id, district_id, is_borrower, is_lender, identity_card_type, founded_date, pic_name, nib_number, source_created_at, source_updated_at
from dedup
where rn = 1