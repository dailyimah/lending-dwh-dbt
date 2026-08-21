{{ config(materialized='view') }}
/*
  stg_company - company customers, ALL versions kept (SCD2 input).
  - naive DATETIME -> UTC (fixed UTC+7 offset, var source_utc_offset_hours)
  - founded STRING in mixed formats -> DATE (NULL if unparseable)
  - drops "no-change" re-touches
*/
with typed as (
    select
        id                                  as customer_id,
        cast('company' as {{ dbt.type_string() }}) as entity_type,
        trim(name)                          as customer_name,
        lower(trim(email))                  as email,
        phone_number,
        country_id, province_id, city_id, district_id,
        cast(is_borrower as boolean)        as is_borrower,
        cast(is_lender  as boolean)         as is_lender,
        upper(identity_card_type)           as identity_card_type,
        case                                -- founded is STRING in mixed formats; unknown shapes -> NULL
            when length(founded) = 4  then cast(founded || '-01-01' as date)                                   -- 'YYYY'
            when length(founded) = 10 then cast(founded as date)                                               -- 'YYYY-MM-DD'
            when length(founded) = 7  then cast(substr(founded, 4, 4) || '-' || substr(founded, 1, 2) || '-01' as date)  -- 'MM/YYYY'
        end                                 as founded_date,
        trim(pic_name)                      as pic_name,
        nib_number,
        {{ dbt.dateadd('hour', -1 * var('source_utc_offset_hours'), 'cast(created_at as timestamp)') }}    as source_created_at,
        {{ dbt.dateadd('hour', -1 * var('source_utc_offset_hours'), 'cast(updated_at as timestamp)') }}    as source_updated_at
    from {{ ref('company') }}
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
