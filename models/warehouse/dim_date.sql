{{ config(materialized='table') }}
/* dim_date - generated calendar, one row per day. Natural key: date_day. */
with spine as (
    {{ dbt_utils.date_spine(datepart="day", start_date="cast('2024-01-01' as date)", end_date="cast('2028-01-01' as date)") }}
)
select
    cast(date_day as date)                                          as date_day,
    extract(year  from date_day)                                    as year_no,
    extract(month from date_day)                                    as month_no,
    cast(extract(year from date_day) * 100 + extract(month from date_day) as integer) as year_month_no,
    cast({{ dbt.date_trunc('month', 'date_day') }} as date)         as month_start_date,
    cast(date_day as date) = last_day(cast(date_day as date))       as is_month_end
from spine
