{{ config(
    materialized='table',
    partition_by=bq_partition('disbursed_date', 'month'),
    cluster_by=['loan_type_id', 'borrower_customer_id']
) }}
/*
  fact_loan - ACCUMULATING SNAPSHOT. Grain: one row per loan, updated as milestones occur.
  Carries lifecycle milestone timestamps (funnel), current status from history, channel,
  funding/insurance roll-ups, schedule + repayment totals and outstanding principal.
  borrower_customer_key = dim_customer version valid at request time (point-in-time).
*/
with l as (
    select * from {{ ref('stg_loan') }}
),
ms as (
    select * from {{ ref('int_loan_milestones') }}
),
cust_asof as (
    select l.loan_id, d.customer_key,
           row_number() over (partition by l.loan_id order by d.valid_from desc) as rn
    from l
    join {{ ref('dim_customer') }} d
      on d.customer_id = l.borrower_customer_id
     and d.valid_from <= l.requested_at
     and d.valid_to   >  l.requested_at
),
cust_earliest as (   -- late-arriving dimension: loan requested before the first customer version
    select l.loan_id, d.customer_key,
           row_number() over (partition by l.loan_id order by d.valid_from asc) as rn
    from l
    join {{ ref('dim_customer') }} d on d.customer_id = l.borrower_customer_id
),
lh as (
    select * from {{ ref('stg_loanhub_loan') }}
),
dsb as (
    select loan_id, bank_id, disbursement_method, disbursement_status,
           row_number() over (partition by loan_id order by disbursed_at desc) as rn
    from {{ ref('stg_disbursement') }}
),
ins as (
    select loan_id, premium_amount, insurance_vendor, insurance_status from {{ ref('stg_insurance') }}
),
fnd as (
    select loan_id,
           count(*)                 as lender_count,
           sum(committed_amount)    as funded_amount_total,
           sum(fund_ratio)          as fund_ratio_total
    from {{ ref('stg_fund') }}
    group by loan_id
),
sch as (
    select loan_id,
           count(*)            as installment_count,
           sum(due_principal)  as scheduled_principal_total,
           sum(due_interest)   as scheduled_interest_total,
           sum(due_amount)     as scheduled_amount_total,
           min(due_date)       as first_due_date,
           max(due_date)       as maturity_date
    from {{ ref('stg_repayment_schedule') }}
    group by loan_id
),
pay as (
    select loan_id,
           sum(allocated_amount)    as paid_amount_total,
           sum(allocated_principal) as paid_principal_total,
           sum(allocated_interest)  as paid_interest_total,
           max(paid_date)           as last_paid_date,
           count(distinct transfer_id) as transfer_count
    from {{ ref('int_repayment_allocation') }}
    group by loan_id
)
select
    l.loan_id,
    l.borrower_customer_id,
    coalesce(ca.customer_key, ce.customer_key, '{{ var("unknown_member_key") }}#1') as borrower_customer_key,
    l.loan_type_id,
    coalesce(lh.partner_id, '{{ var("direct_channel_key") }}')  as partner_id,
    case when lh.loan_id is not null then 'partner' else 'direct' end as origination_channel,
    lh.loan_reference_id                                        as partner_loan_reference_id,
    lh.partner_commission_pa,

    -- terms
    l.tenor_months,
    l.repayment_mode,
    l.grade,
    l.nominal_request,
    l.nominal_loan,
    l.nominal_request - l.nominal_loan                          as approval_haircut_amount,
    case when l.nominal_request > 0
         then cast((l.nominal_request - l.nominal_loan) as {{ dbt.type_float() }}) / cast(l.nominal_request as {{ dbt.type_float() }})
         end                                                    as approval_haircut_pct,

    -- status (history is the source of truth)
    ms.current_status_name,
    s_hist.movement_id                                          as current_movement_id,
    l.current_movement_id                                       as source_movement_id,
    l.current_movement_id is distinct from s_hist.movement_id   as has_status_mismatch,

    -- lifecycle milestones (accumulating snapshot)
    ms.requested_at, ms.approved_at, ms.funding_at, ms.disbursed_at,
    ms.repaid_at, ms.written_off_at, ms.rejected_at, ms.cancelled_at, ms.closed_at,
    cast(ms.disbursed_at as date)                               as disbursed_date,
    cast(ms.closed_at as date)                                  as closed_date,
    cast(extract(year from ms.disbursed_at) * 100 + extract(month from ms.disbursed_at) as integer) as disbursement_cohort,
    {{ dbt.datediff('ms.requested_at', 'ms.approved_at',  'day') }}  as days_request_to_approval,
    {{ dbt.datediff('ms.approved_at',  'ms.disbursed_at', 'day') }}  as days_approval_to_disbursement,
    {{ dbt.datediff('ms.requested_at', 'ms.disbursed_at', 'day') }}  as days_request_to_disbursement,
    ms.movement_count,

    -- disbursement & insurance attributes
    dsb.bank_id                                                 as disbursement_bank_id,
    dsb.disbursement_method,
    ins.loan_id is not null                                     as has_insurance,
    ins.premium_amount                                          as insurance_premium_amount,
    ins.insurance_vendor,

    -- funding roll-up (P2P)
    coalesce(fnd.lender_count, 0)                               as lender_count,
    coalesce(fnd.funded_amount_total, 0)                        as funded_amount_total,
    fnd.fund_ratio_total,

    -- schedule & repayment roll-up
    coalesce(sch.installment_count, 0)                          as installment_count,
    sch.scheduled_principal_total,
    sch.scheduled_interest_total,
    sch.scheduled_amount_total,
    sch.first_due_date,
    sch.maturity_date,
    coalesce(pay.paid_amount_total, 0)                          as paid_amount_total,
    coalesce(pay.paid_principal_total, 0)                       as paid_principal_total,
    coalesce(pay.paid_interest_total, 0)                        as paid_interest_total,
    coalesce(pay.transfer_count, 0)                             as transfer_count,
    pay.last_paid_date,
    case when ms.disbursed_at is not null
         then greatest(l.nominal_loan - coalesce(pay.paid_principal_total, 0), 0) end as outstanding_principal,
    case when ms.written_off_at is not null
         then greatest(l.nominal_loan - coalesce(pay.paid_principal_total, 0), 0) else 0 end as written_off_amount,

    l.source_updated_at
from l
left join ms            on ms.loan_id = l.loan_id
left join {{ ref('stg_movement_status') }} s_hist on s_hist.status_name = ms.current_status_name
left join cust_asof ca  on ca.loan_id = l.loan_id and ca.rn = 1
left join cust_earliest ce on ce.loan_id = l.loan_id and ce.rn = 1
left join lh            on lh.loan_id = l.loan_id
left join dsb           on dsb.loan_id = l.loan_id and dsb.rn = 1
left join ins           on ins.loan_id = l.loan_id
left join fnd           on fnd.loan_id = l.loan_id
left join sch           on sch.loan_id = l.loan_id
left join pay           on pay.loan_id = l.loan_id
