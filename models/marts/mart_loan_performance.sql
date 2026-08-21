{{ config(materialized='table') }}
/*
  mart_loan_performance - loan performance by disbursement cohort (task mart 4c).
  Grain: disbursement_cohort (YYYYMM) x loan_type x partner x grade x repayment_mode.
  Volume, outcomes, collections, write-offs and early-delinquency vintage indicators
  (share of loans reaching 30+ DPD within 90 days of disbursement).
*/
with l as (
    select * from {{ ref('fact_loan') }} where disbursed_at is not null
),
vintage as (
    select
        loan_id,
        max(days_past_due)                                                                  as max_dpd,
        max(case when days_since_disbursement <= 90 and days_past_due > 30 then 1 else 0 end) as hit_30dpd_within_90d,
        max(case when days_since_disbursement <= 90 and days_past_due > 0  then 1 else 0 end) as hit_1dpd_within_90d
    from {{ ref('fact_loan_daily_snapshot') }}
    group by loan_id
),
due as (
    select loan_id,
           sum(case when due_date <= date '{{ var("as_of_date") }}' then due_amount else 0 end) as due_amount_to_date,
           sum(case when due_date <= date '{{ var("as_of_date") }}' then paid_amount else 0 end) as paid_on_due_to_date
    from {{ ref('fact_repayment_schedule') }}
    group by loan_id
)
select
    l.disbursement_cohort,
    l.loan_type_id,
    l.partner_id,
    l.origination_channel,
    l.grade,
    l.repayment_mode,
    count(*)                                                            as loans_disbursed,
    sum(case when {{ dbt.datediff('l.disbursed_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} >= 90 then 1 else 0 end) as loans_mature_90d,
    sum(case when l.first_due_date is not null and ({{ dbt.datediff('l.first_due_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} > 30 or l.first_fully_paid_date is not null) then 1 else 0 end) as loans_with_observable_fpd,
    sum(case when l.is_fpd then 1 else 0 end)                           as loans_fpd,
    avg(l.credit_score_at_request)                                      as avg_credit_score_at_origination,
    sum(l.nominal_loan)                                                 as disbursed_amount,
    avg(l.nominal_loan)                                                 as avg_ticket_size,
    avg(l.tenor_months)                                                 as avg_tenor_months,
    sum(case when l.current_status_name = 'repaid'      then 1 else 0 end) as loans_repaid,
    sum(case when l.current_status_name = 'written_off' then 1 else 0 end) as loans_written_off,
    sum(case when l.current_status_name = 'disbursed'   then 1 else 0 end) as loans_active,
    sum(l.written_off_amount)                                           as written_off_amount,
    sum(l.outstanding_principal)                                        as outstanding_principal,
    sum(l.paid_principal_total)                                         as principal_collected,
    sum(l.paid_interest_total)                                          as interest_collected,
    sum(l.paid_amount_total)                                            as total_collected,
    sum(d.due_amount_to_date)                                           as due_amount_to_date,
    case when sum(d.due_amount_to_date) > 0
         then cast(sum(d.paid_on_due_to_date) as {{ dbt.type_float() }}) / cast(sum(d.due_amount_to_date) as {{ dbt.type_float() }}) end as collection_rate,
    case when sum(l.nominal_loan) > 0
         then cast(sum(l.written_off_amount) as {{ dbt.type_float() }}) / cast(sum(l.nominal_loan) as {{ dbt.type_float() }}) end as write_off_rate_by_amount,
    cast(sum(case when l.current_status_name = 'written_off' then 1 else 0 end) as {{ dbt.type_float() }}) / count(*) as write_off_rate_by_count,
    avg(v.max_dpd)                                                      as avg_max_dpd,
    -- vintage shares use only loans old enough to have been observed for the full window
    case when sum(case when {{ dbt.datediff('l.disbursed_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} >= 90 then 1 else 0 end) > 0
         then cast(sum(case when {{ dbt.datediff('l.disbursed_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} >= 90 then v.hit_1dpd_within_90d else 0 end) as {{ dbt.type_float() }})
              / sum(case when {{ dbt.datediff('l.disbursed_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} >= 90 then 1 else 0 end) end as share_1dpd_within_90d,
    case when sum(case when {{ dbt.datediff('l.disbursed_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} >= 90 then 1 else 0 end) > 0
         then cast(sum(case when {{ dbt.datediff('l.disbursed_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} >= 90 then v.hit_30dpd_within_90d else 0 end) as {{ dbt.type_float() }})
              / sum(case when {{ dbt.datediff('l.disbursed_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} >= 90 then 1 else 0 end) end as share_30dpd_within_90d,
    case when sum(case when l.first_due_date is not null and ({{ dbt.datediff('l.first_due_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} > 30 or l.first_fully_paid_date is not null) then 1 else 0 end) > 0
         then cast(sum(case when l.is_fpd then 1 else 0 end) as {{ dbt.type_float() }})
              / sum(case when l.first_due_date is not null and ({{ dbt.datediff('l.first_due_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} > 30 or l.first_fully_paid_date is not null) then 1 else 0 end) end as fpd_rate,
    avg(l.days_request_to_disbursement)                                 as avg_days_request_to_disbursement,
    avg(l.approval_haircut_pct)                                         as avg_approval_haircut_pct,
    avg(l.lender_count)                                                 as avg_lender_count,
    avg(case when l.has_insurance then 1.0 else 0.0 end)                as insured_share,
    date '{{ var("as_of_date") }}'                                                  as as_of_date
from l
left join vintage v on v.loan_id = l.loan_id
left join due d     on d.loan_id = l.loan_id
group by 1, 2, 3, 4, 5, 6
