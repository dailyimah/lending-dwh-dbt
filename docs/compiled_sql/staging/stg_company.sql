
/*
  stg_company - company customers, ALL versions kept (SCD2 input).
  - naive DATETIME -> UTC (assumed reporting_timezone)
  - founded STRING in mixed formats -> DATE (NULL if unparseable)
  - drops "no-change" re-touches
*/
with typed as (
    select
        id                                  as customer_id,
        cast('company' as TEXT) as entity_type,
        trim(name)                          as customer_name,
        lower(trim(email))                  as email,
        phone_number,
        country_id, province_id, city_id, district_id,
        cast(is_borrower as boolean)        as is_borrower,
        cast(is_lender  as boolean)         as is_lender,
        upper(identity_card_type)           as identity_card_type,
        case
    when regexp_matches(founded, '^[0-9]{4}$')
      then cast(try_strptime(concat(founded, '-01-01'), '%Y-%m-%d') as date)
    when regexp_matches(founded, '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
      then cast(try_strptime(founded, '%Y-%m-%d') as date)
    when regexp_matches(founded, '^[0-9]{2}/[0-9]{4}$')
      then cast(try_strptime(concat('01/', founded), '%d/%m/%Y') as date)
    else null
  end      as founded_date,
        trim(pic_name)                      as pic_name,
        nib_number,
        timezone('UTC', timezone('Asia/Jakarta', cast(created_at as timestamp)))    as source_created_at,
        timezone('UTC', timezone('Asia/Jakarta', cast(updated_at as timestamp)))    as source_updated_at
    from "fazz_dwh"."main_raw"."company"
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