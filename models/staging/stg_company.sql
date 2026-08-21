{{ config(materialized='view') }}
/*
  stg_company - company customers, ALL versions kept (SCD2 input).
  - naive DATETIME -> UTC (fixed UTC+7 offset, var source_utc_offset_hours)
  - founded STRING -> DATE for three recognised shapes; other shapes or invalid dates -> NULL
  - drops re-touches identical to the previous row
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
        case                                -- founded is a free STRING; shapes recognised: 'YYYY' | 'YYYY-MM-DD' | 'MM/YYYY'
            when length(founded) = 4 then {{ safe_cast_date("founded || '-01-01'") }}
            when length(founded) = 10 and substr(founded, 5, 1) = '-' and substr(founded, 8, 1) = '-' then {{ safe_cast_date('founded') }}
            when length(founded) = 7  and substr(founded, 3, 1) = '/' then {{ safe_cast_date("substr(founded, 4, 4) || '-' || substr(founded, 1, 2) || '-01'") }}
        end                                 as founded_date,
        trim(pic_name)                      as pic_name,
        nib_number,
        {{ dbt.dateadd('hour', -1 * var('source_utc_offset_hours'), 'cast(created_at as timestamp)') }}    as source_created_at,
        {{ dbt.dateadd('hour', -1 * var('source_utc_offset_hours'), 'cast(updated_at as timestamp)') }}    as source_updated_at
    from {{ ref('company') }}
),
hashed as (
    select *, {{ dbt.hash(dbt.concat(["coalesce(cast(customer_name as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(email as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(phone_number as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(country_id as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(province_id as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(city_id as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(district_id as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(is_borrower as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(is_lender as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(identity_card_type as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(founded_date as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(pic_name as " ~ dbt.type_string() ~ "), '')", "'|'", "coalesce(cast(nib_number as " ~ dbt.type_string() ~ "), '')"])) }} as content_hash
    from typed
),
flagged as (
    select *,
           lag(content_hash) over (partition by customer_id order by source_updated_at) as prev_hash
    from hashed
)
select customer_id, entity_type, customer_name, email, phone_number, country_id, province_id, city_id, district_id,
       is_borrower, is_lender, identity_card_type, founded_date, pic_name, nib_number,
       source_created_at, source_updated_at
from flagged
where prev_hash is null or prev_hash <> content_hash
