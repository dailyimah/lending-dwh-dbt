{{ config(materialized='table', cluster_by=['customer_id']) }}
/*
  mart_customer_360 - one row per CURRENT customer, descriptive attributes from dim_customer
  plus computed behaviour metrics from the facts (borrower side + lender side).
  Metrics live here, never in the SCD2 dimension. Base for mart_credit_score_by_segment
  and for lender-portfolio / concentration questions.
*/
with cur as (
    select * from {{ ref('dim_customer') }} where is_current and customer_id <> '{{ var("unknown_member_key") }}'
),
loans as (
    select
        borrower_customer_id as customer_id,
        count(*)                                                           as loans_count,
        sum(case when disbursed_at is not null then 1 else 0 end)          as loans_disbursed_count,
        sum(case when current_status_name = 'repaid'      then 1 else 0 end) as loans_repaid_count,
        sum(case when current_status_name = 'written_off' then 1 else 0 end) as loans_written_off_count,
        sum(case when current_status_name = 'disbursed'   then 1 else 0 end) as loans_active_count,
        sum(case when current_status_name = 'rejected'    then 1 else 0 end) as loans_rejected_count,
        sum(nominal_request)                                               as total_requested_amount,
        sum(case when disbursed_at is not null then nominal_loan else 0 end) as total_disbursed_amount,
        sum(case when current_status_name = 'disbursed' then outstanding_principal else 0 end) as current_outstanding_principal,
        sum(written_off_amount)                                            as total_written_off_amount,
        sum(paid_amount_total)                                             as total_paid_amount,
        sum(paid_interest_total)                                           as total_paid_interest,
        avg(approval_haircut_pct)                                          as avg_approval_haircut_pct,
        min(requested_at)                                                  as first_loan_requested_at,
        min(disbursed_date)                                                as first_disbursed_date,
        max(disbursed_date)                                                as last_disbursed_date,
        avg(tenor_months)                                                  as avg_tenor_months
    from {{ ref('fact_loan') }}
    group by borrower_customer_id
),
snap as (
    select
        l.borrower_customer_id as customer_id,
        max(s.days_past_due)                                               as max_dpd_ever,
        max(case when s.snapshot_date = {{ as_of_date() }} and s.is_active then s.days_past_due else 0 end) as current_dpd,
        max(case when s.is_npl_90 then 1 else 0 end) = 1                   as ever_npl_90
    from {{ ref('fact_loan_daily_snapshot') }} s
    join {{ ref('fact_loan') }} l on l.loan_id = s.loan_id
    group by l.borrower_customer_id
),
sched as (
    select
        l.borrower_customer_id as customer_id,
        count(*)                                                           as installments_due_count,
        sum(case when s.is_fully_paid and s.fully_paid_date <= s.due_date then 1 else 0 end) as installments_paid_on_time_count,
        sum(case when s.is_fully_paid then 1 else 0 end)                   as installments_paid_count,
        avg(case when s.is_fully_paid then greatest(s.days_late_to_full_payment, 0) end) as avg_days_late
    from {{ ref('fact_repayment_schedule') }} s
    join {{ ref('fact_loan') }} l on l.loan_id = s.loan_id
    where s.due_date <= {{ as_of_date() }}
    group by l.borrower_customer_id
),
funding as (
    select
        lender_customer_id as customer_id,
        count(*)                                                           as fundings_count,
        count(distinct loan_id)                                            as loans_funded_count,
        sum(committed_amount)                                              as total_committed_amount,
        sum(settled_amount)                                                as total_settled_amount,
        sum(current_exposure_amount)                                       as current_exposure_amount,
        sum(case when is_loan_active then 1 else 0 end)                    as active_fundings_count,
        avg(fund_ratio)                                                    as avg_fund_ratio,
        min(funded_date)                                                   as first_funded_date,
        max(funded_date)                                                   as last_funded_date
    from {{ ref('fact_funding') }}
    group by lender_customer_id
)
select
    c.customer_key, c.customer_id, c.entity_type, c.customer_role, c.lender_type, c.origination_channel,
    c.customer_name, c.province_id, c.city_id, c.district_id, c.identity_card_type,
    c.credit_score, c.credit_grade, c.sequence_no as customer_version_count,
    c.source_created_at as customer_since,

    -- borrower metrics
    coalesce(l.loans_count, 0)                  as loans_count,
    coalesce(l.loans_disbursed_count, 0)        as loans_disbursed_count,
    coalesce(l.loans_repaid_count, 0)           as loans_repaid_count,
    coalesce(l.loans_written_off_count, 0)      as loans_written_off_count,
    coalesce(l.loans_active_count, 0)           as loans_active_count,
    coalesce(l.loans_rejected_count, 0)         as loans_rejected_count,
    coalesce(l.loans_disbursed_count, 0) > 1    as is_repeat_borrower,
    coalesce(l.total_requested_amount, 0)       as total_requested_amount,
    coalesce(l.total_disbursed_amount, 0)       as total_disbursed_amount,
    coalesce(l.current_outstanding_principal, 0) as current_outstanding_principal,
    coalesce(l.total_written_off_amount, 0)     as total_written_off_amount,
    coalesce(l.total_paid_amount, 0)            as total_paid_amount,
    coalesce(l.total_paid_interest, 0)          as total_paid_interest,
    l.avg_approval_haircut_pct,
    l.avg_tenor_months,
    l.first_loan_requested_at, l.first_disbursed_date, l.last_disbursed_date,
    coalesce(sn.max_dpd_ever, 0)                as max_dpd_ever,
    coalesce(sn.current_dpd, 0)                 as current_dpd,
    {{ dpd_bucket('coalesce(sn.current_dpd, 0)') }} as current_dpd_bucket,
    coalesce(sn.ever_npl_90, false)             as ever_npl_90,
    coalesce(sc.installments_due_count, 0)      as installments_due_count,
    coalesce(sc.installments_paid_count, 0)     as installments_paid_count,
    coalesce(sc.installments_paid_on_time_count, 0) as installments_paid_on_time_count,
    case when sc.installments_due_count > 0
         then cast(sc.installments_paid_on_time_count as {{ dbt.type_float() }}) / sc.installments_due_count end as on_time_repayment_rate,
    sc.avg_days_late,

    -- lender metrics
    coalesce(f.fundings_count, 0)               as fundings_count,
    coalesce(f.loans_funded_count, 0)           as loans_funded_count,
    coalesce(f.total_committed_amount, 0)       as total_committed_amount,
    coalesce(f.total_settled_amount, 0)         as total_settled_amount,
    coalesce(f.current_exposure_amount, 0)      as current_exposure_amount,
    coalesce(f.active_fundings_count, 0)        as active_fundings_count,
    f.avg_fund_ratio,
    f.first_funded_date, f.last_funded_date,

    {{ as_of_date() }}                          as as_of_date
from cur c
left join loans   l  on l.customer_id  = c.customer_id
left join snap    sn on sn.customer_id = c.customer_id
left join sched   sc on sc.customer_id = c.customer_id
left join funding f  on f.customer_id  = c.customer_id
