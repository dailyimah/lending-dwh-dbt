
/*
  mart_delinquency - delinquency rates (task mart 4b) and portfolio quality over time.
  Grain: one row per snapshot_date x loan_type x partner x grade, with OJK DPD buckets as
  columns and the standard ratios: delinquency rate (DPD > 0), PAR30 (DPD > 30),
  NPL90 (DPD > 90) and TKB90 = 1 - NPL90. is_month_end / is_latest flags support reporting
  cadences. Roll up over any dimension by summing the amount columns and recomputing ratios.
*/
with s as (
    select * from "fazz_dwh"."main_warehouse"."fact_loan_daily_snapshot"
),
agg as (
    select
        snapshot_date,
        loan_type_id,
        partner_id,
        grade,
        count(*)                                                              as loans_on_book,
        sum(case when is_active then 1 else 0 end)                            as loans_active,
        sum(case when is_active then outstanding_principal else 0 end)        as outstanding_principal,
        sum(case when is_active then overdue_amount else 0 end)               as overdue_amount,
        sum(case when is_active and dpd_bucket_order = 0 then outstanding_principal else 0 end) as outstanding_current,
        sum(case when is_active and dpd_bucket_order = 1 then outstanding_principal else 0 end) as outstanding_dpd_1_30,
        sum(case when is_active and dpd_bucket_order = 2 then outstanding_principal else 0 end) as outstanding_dpd_31_60,
        sum(case when is_active and dpd_bucket_order = 3 then outstanding_principal else 0 end) as outstanding_dpd_61_90,
        sum(case when is_active and dpd_bucket_order = 4 then outstanding_principal else 0 end) as outstanding_dpd_90_plus,
        sum(case when is_active and is_delinquent then 1 else 0 end)          as loans_delinquent,
        sum(case when is_active and days_past_due > 30 then 1 else 0 end)     as loans_par30,
        sum(case when is_active and is_npl_90 then 1 else 0 end)              as loans_npl_90,
        sum(case when is_active and is_delinquent then outstanding_principal else 0 end) as outstanding_delinquent,
        sum(case when is_active and days_past_due > 30 then outstanding_principal else 0 end) as outstanding_par30,
        sum(case when is_active and is_npl_90 then outstanding_principal else 0 end)  as outstanding_npl_90,
        sum(case when is_closing_day and status_name = 'written_off' then 1 else 0 end) as loans_written_off_today,
        sum(case when is_closing_day and status_name = 'repaid' then 1 else 0 end)      as loans_repaid_today
    from s
    group by 1, 2, 3, 4
)
select
    a.*,
    case when loans_active > 0 then cast(loans_delinquent as float) / loans_active end           as delinquency_rate_by_count,
    case when outstanding_principal > 0 then cast(outstanding_delinquent as float) / cast(outstanding_principal as float) end as delinquency_rate_by_amount,
    case when outstanding_principal > 0 then cast(outstanding_par30 as float) / cast(outstanding_principal as float) end       as par30_rate,
    case when outstanding_principal > 0 then cast(outstanding_npl_90 as float) / cast(outstanding_principal as float) end      as npl90_rate,
    case when outstanding_principal > 0 then 1 - cast(outstanding_npl_90 as float) / cast(outstanding_principal as float) end  as tkb90,
    d.year_month_no,
    a.snapshot_date = 

    (

    (d.month_start_date + cast(1 as bigint) * interval 1 month) + cast(-1 as bigint) * interval 1 day) as is_month_end,
    a.snapshot_date = cast('2026-08-21' as date)                                      as is_latest
from agg a
join "fazz_dwh"."main_warehouse"."dim_date" d on d.date_day = a.snapshot_date