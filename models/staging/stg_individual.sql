{{ config(materialized='view') }}
/*
  stg_individual - individual customers, ALL versions kept (SCD2 input).
  - naive DATETIME -> UTC (fixed UTC+7 offset, var source_utc_offset_hours)
  - drops re-touches identical to the PREVIOUS row (a change back to an earlier state is kept)
  - shaped to the unified customer contract (company-only columns NULL)
*/
with typed as (
    select
        id                                  as customer_id,
        cast('individual' as {{ dbt.type_string() }}) as entity_type,
        trim(name)                          as customer_name,
        lower(trim(email))                  as email,
        phone_number,
        country_id, province_id, city_id, district_id,
        cast(is_borrower as boolean)        as is_borrower,
        cast(is_lender  as boolean)         as is_lender,
        upper(identity_card_type)           as identity_card_type,
        cast(null as date)                  as founded_date,
        cast(null as {{ dbt.type_string() }}) as pic_name,
        cast(null as {{ dbt.type_string() }}) as nib_number,
        {{ dbt.dateadd('hour', -1 * var('source_utc_offset_hours'), 'cast(created_at as timestamp)') }}    as source_created_at,
        {{ dbt.dateadd('hour', -1 * var('source_utc_offset_hours'), 'cast(updated_at as timestamp)') }}    as source_updated_at
    from {{ ref('individual') }}
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
