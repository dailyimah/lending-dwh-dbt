{{ config(materialized='table', partition_by=bq_partition('snapshot_date'), cluster_by=['loan_type_id']) }}
/*
  mart_delinquency - delinquency rates (task mart 4b) and portfolio quality over time.
  Grain: one row per snapshot_date x loan_type x partner x grade, with OJK DPD buckets as
  columns and the standard ratios: delinquency rate (DPD > 0), PAR30 (DPD > 30),
  NPL90 (DPD > 90) and TKB90 = 1 - NPL90. is_month_end / is_latest flags support reporting
  cadences. Roll up over any dimension by summing the amount columns and recomputing ratios.
*/
with s as (
    select * from {{ ref('fact_loan_daily_snapshot') }}
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
        sum(case when is_active and dpd_bucket = 'current' then outstanding_principal else 0 end) as outstanding_current,
        sum(case when is_active and dpd_bucket = '1-30' then outstanding_principal else 0 end) as outstanding_dpd_1_30,
        sum(case when is_active and dpd_bucket = '31-60' then outstanding_principal else 0 end) as outstanding_dpd_31_60,
        sum(case when is_active and dpd_bucket = '61-90' then outstanding_principal else 0 end) as outstanding_dpd_61_90,
        sum(case when is_active and dpd_bucket = '90+' then outstanding_principal else 0 end) as outstanding_dpd_90_plus,
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
    case when loans_active > 0 then cast(loans_delinquent as {{ dbt.type_float() }}) / loans_active end           as delinquency_rate_by_count,
    case when outstanding_principal > 0 then cast(outstanding_delinquent as {{ dbt.type_float() }}) / cast(outstanding_principal as {{ dbt.type_float() }}) end as delinquency_rate_by_amount,
    case when outstanding_principal > 0 then cast(outstanding_par30 as {{ dbt.type_float() }}) / cast(outstanding_principal as {{ dbt.type_float() }}) end       as par30_rate,
    case when outstanding_principal > 0 then cast(outstanding_npl_90 as {{ dbt.type_float() }}) / cast(outstanding_principal as {{ dbt.type_float() }}) end      as npl90_rate,
    case when outstanding_principal > 0 then 1 - cast(outstanding_npl_90 as {{ dbt.type_float() }}) / cast(outstanding_principal as {{ dbt.type_float() }}) end  as tkb90,
    d.year_month_no,
    d.is_month_end,
    a.snapshot_date = {{ as_of_date() }}                                      as is_latest
from agg a
join {{ ref('dim_date') }} d on d.date_day = a.snapshot_date
