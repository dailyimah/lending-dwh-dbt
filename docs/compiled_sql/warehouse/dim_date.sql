
/* dim_date - generated calendar, one row per day. Natural key: date_day. */
with spine as (
    select cast(d as date) as date_day
  from generate_series(date '2024-01-01', date '2027-12-31', interval 1 day) as t(d)
)
select
    date_day,
    extract(year    from date_day)                       as year_no,
    extract(quarter from date_day)                       as quarter_no,
    extract(month   from date_day)                       as month_no,
    extract(day     from date_day)                       as day_of_month,
    isodow(date_day)                        as day_of_week,     -- 1 = Mon ... 7 = Sun
    isodow(date_day) in (6, 7)              as is_weekend,
    cast(date_trunc('month', date_day) as date) as month_start_date,
    cast(date_trunc('quarter', date_day) as date) as quarter_start_date,
    cast(date_trunc('year', date_day) as date) as year_start_date,
    cast(extract(year from date_day) * 100 + extract(month from date_day) as integer) as year_month_no   -- e.g. 202603
from spine