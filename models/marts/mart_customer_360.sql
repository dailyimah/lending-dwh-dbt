{{ config(materialized='table', cluster_by=['customer_id']) }}
/*
  mart_customer_360 - one row per CURRENT customer: attributes from dim_customer plus behaviour
  metrics from the facts (borrower side and lender side). Metrics live here, not in the SCD2
  dimension, otherwise every repayment would open a new customer version.
*/
with cur as (
    select * from {{ ref('dim_customer') }} where is_current and customer_id <> 'UNKNOWN'
),
loans as (
    select
        borrower_customer_id as customer_id,
        count(*)                                                             as loans_count,
        sum(case when disbursed_at is not null then 1 else 0 end)            as loans_disbursed_count,
        sum(case when current_status_name = 'repaid'      then 1 else 0 end) as loans_repaid_count,
        sum(case when current_status_name = 'written_off' then 1 else 0 end) as loans_written_off_count,
        sum(case when current_status_name = 'disbursed'   then 1 else 0 end) as loans_active_count,
        sum(case when disbursed_at is not null then nominal_loan else 0 end) as total_disbursed_amount,
        sum(case when current_status_name = 'disbursed' then outstanding_principal else 0 end) as current_outstanding_principal,
        sum(written_off_amount)                                              as total_written_off_amount,
        sum(paid_amount_total)                                               as total_paid_amount
    from {{ ref('fact_loan') }}
    group by borrower_customer_id
),
snap as (
    select
        l.borrower_customer_id as customer_id,
        max(s.days_past_due)                                                 as max_dpd_ever,
        max(case when s.snapshot_date = {{ as_of_date() }} and s.is_active then s.days_past_due else 0 end) as current_dpd,
        max(case when s.is_npl_90 then 1 else 0 end) = 1                     as ever_npl_90
    from {{ ref('fact_loan_daily_snapshot') }} s
    join {{ ref('fact_loan') }} l on l.loan_id = s.loan_id
    group by l.borrower_customer_id
),
sched as (
    select
        l.borrower_customer_id as customer_id,
        count(*)                                                             as installments_due_count,
        sum(case when s.is_fully_paid and s.fully_paid_date <= s.due_date then 1 else 0 end) as installments_paid_on_time_count
    from {{ ref('fact_repayment_schedule') }} s
    join {{ ref('fact_loan') }} l on l.loan_id = s.loan_id
    where s.due_date <= {{ as_of_date() }}
    group by l.borrower_customer_id
),
funding as (
    select
        lender_customer_id as customer_id,
        count(*)                     as fundings_count,
        sum(committed_amount)        as total_committed_amount,
        sum(current_exposure_amount) as current_exposure_amount
    from {{ ref('fact_funding') }}
    group by lender_customer_id
)
select
    c.customer_key, c.customer_id, c.entity_type, c.customer_role, c.lender_type, c.origination_channel,
    c.province_id, c.city_id, c.credit_score, c.credit_grade,

    -- borrower metrics
    coalesce(l.loans_count, 0)                   as loans_count,
    coalesce(l.loans_disbursed_count, 0)         as loans_disbursed_count,
    coalesce(l.loans_repaid_count, 0)            as loans_repaid_count,
    coalesce(l.loans_written_off_count, 0)       as loans_written_off_count,
    coalesce(l.loans_active_count, 0)            as loans_active_count,
    coalesce(l.loans_disbursed_count, 0) > 1     as is_repeat_borrower,
    coalesce(l.total_disbursed_amount, 0)        as total_disbursed_amount,
    coalesce(l.current_outstanding_principal, 0) as current_outstanding_principal,
    coalesce(l.total_written_off_amount, 0)      as total_written_off_amount,
    coalesce(l.total_paid_amount, 0)             as total_paid_amount,
    coalesce(sn.max_dpd_ever, 0)                 as max_dpd_ever,
    coalesce(sn.current_dpd, 0)                  as current_dpd,
    {{ dpd_bucket('coalesce(sn.current_dpd, 0)') }} as current_dpd_bucket,
    coalesce(sn.ever_npl_90, false)              as ever_npl_90,
    coalesce(sc.installments_due_count, 0)       as installments_due_count,
    coalesce(sc.installments_paid_on_time_count, 0) as installments_paid_on_time_count,
    case when sc.installments_due_count > 0
         then cast(sc.installments_paid_on_time_count as {{ dbt.type_float() }}) / sc.installments_due_count end as on_time_repayment_rate,

    -- lender metrics
    coalesce(f.fundings_count, 0)                as fundings_count,
    coalesce(f.total_committed_amount, 0)        as total_committed_amount,
    coalesce(f.current_exposure_amount, 0)       as current_exposure_amount,

    {{ as_of_date() }}                           as as_of_date
from cur c
left join loans   l  on l.customer_id  = c.customer_id
left join snap    sn on sn.customer_id = c.customer_id
left join sched   sc on sc.customer_id = c.customer_id
left join funding f  on f.customer_id  = c.customer_id
