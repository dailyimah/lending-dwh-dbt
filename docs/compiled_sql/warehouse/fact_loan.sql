
/*
  fact_loan - ACCUMULATING SNAPSHOT. Grain: one row per loan, updated as milestones occur.
  Carries lifecycle milestone timestamps (funnel), current status from history, channel,
  funding/insurance roll-ups, schedule + repayment totals and outstanding principal.
  borrower_customer_key = dim_customer version valid at request time (point-in-time).
*/
with  __dbt__cte__int_loan_milestones as (

/*
  int_loan_milestones - one row per loan with the FIRST time each lifecycle status
  was reached (from loan_movement history), plus the current status derived from
  history. loan.movement_status_id is kept alongside so disagreement can be tested.
*/
with mv as (
    select m.loan_id, m.moved_at, s.status_name, d.lifecycle_order
    from "fazz_dwh"."main_staging"."stg_loan_movement" m
    join "fazz_dwh"."main_staging"."stg_movement_status" s on s.movement_id = m.movement_id
    join "fazz_dwh"."main_warehouse"."dim_movement_status" d on d.movement_id = m.movement_id
),
pivoted as (
    select
        loan_id,
        min(case when status_name = 'requested'   then moved_at end) as requested_at,
        min(case when status_name = 'approved'    then moved_at end) as approved_at,
        min(case when status_name = 'rejected'    then moved_at end) as rejected_at,
        min(case when status_name = 'cancelled'   then moved_at end) as cancelled_at,
        min(case when status_name = 'funding'     then moved_at end) as funding_at,
        min(case when status_name = 'disbursed'   then moved_at end) as disbursed_at,
        min(case when status_name = 'repaid'      then moved_at end) as repaid_at,
        min(case when status_name = 'written_off' then moved_at end) as written_off_at,
        count(*)                                                      as movement_count
    from mv
    group by loan_id
),
latest as (
    select loan_id, status_name as current_status_name,
           -- latest by time; identical timestamps resolved by lifecycle order (defensive)
           row_number() over (partition by loan_id order by moved_at desc, lifecycle_order desc) as rn
    from mv
)
select
    p.*,
    l.current_status_name,
    coalesce(p.repaid_at, p.written_off_at, p.rejected_at, p.cancelled_at) as closed_at
from pivoted p
join latest l on l.loan_id = p.loan_id and l.rn = 1
),  __dbt__cte__int_repayment_allocation as (

/*
  int_repayment_allocation - allocates each raw transfer to installments.
  Rule (var payment_allocation_rule = oldest_due_first): a loan's payments fill its
  installments in due-date order. Implemented as an interval overlap between the
  cumulative paid amount (by paid_at) and the cumulative due amount (by installment_no).
  Principal/interest split of each allocation is proportional to the installment's split.
  Any amount beyond the total scheduled is emitted with installment_no NULL (overpayment).
*/
with sched as (
    select
        loan_id, schedule_id, installment_no, due_date, due_principal, due_interest, due_amount,
        sum(due_amount) over (partition by loan_id order by installment_no
                              rows between unbounded preceding and 1 preceding) as cum_due_start,
        sum(due_amount) over (partition by loan_id order by installment_no
                              rows between unbounded preceding and current row) as cum_due_end
    from "fazz_dwh"."main_staging"."stg_repayment_schedule"
),
paid as (
    select
        loan_id, repayment_id, transfer_id, paid_at, paid_date, payment_channel, paid_amount,
        sum(paid_amount) over (partition by loan_id order by paid_at, repayment_id
                               rows between unbounded preceding and 1 preceding) as cum_paid_start,
        sum(paid_amount) over (partition by loan_id order by paid_at, repayment_id
                               rows between unbounded preceding and current row) as cum_paid_end
    from "fazz_dwh"."main_staging"."stg_repayment"
),
overlap as (
    select
        p.loan_id, p.repayment_id, p.transfer_id, p.paid_at, p.paid_date, p.payment_channel, p.paid_amount,
        s.schedule_id, s.installment_no, s.due_date, s.due_principal, s.due_interest, s.due_amount,
        least(p.cum_paid_end, s.cum_due_end) - greatest(coalesce(p.cum_paid_start, 0), coalesce(s.cum_due_start, 0)) as allocated_amount
    from paid p
    join sched s
      on s.loan_id = p.loan_id
     and least(p.cum_paid_end, s.cum_due_end) > greatest(coalesce(p.cum_paid_start, 0), coalesce(s.cum_due_start, 0))
),
overpaid as (
    select
        p.loan_id, p.repayment_id, p.transfer_id, p.paid_at, p.paid_date, p.payment_channel, p.paid_amount,
        cast(null as TEXT) as schedule_id,
        cast(null as integer) as installment_no,
        cast(null as date)    as due_date,
        cast(0 as numeric(28,6)) as due_principal,
        cast(0 as numeric(28,6)) as due_interest,
        cast(0 as numeric(28,6)) as due_amount,
        p.cum_paid_end - greatest(coalesce(p.cum_paid_start, 0), t.total_due) as allocated_amount
    from paid p
    join (select loan_id, sum(due_amount) as total_due from sched group by loan_id) t on t.loan_id = p.loan_id
    where p.cum_paid_end > t.total_due
      and p.cum_paid_end - greatest(coalesce(p.cum_paid_start, 0), t.total_due) > 0
),
unioned as (
    select * from overlap
    union all
    select * from overpaid
)
select
    *,
    case when due_amount > 0 then allocated_amount * (due_principal / due_amount) else 0 end as allocated_principal,
    case when due_amount > 0 then allocated_amount * (due_interest  / due_amount) else 0 end as allocated_interest
from unioned
), l as (
    select * from "fazz_dwh"."main_staging"."stg_loan"
),
ms as (
    select * from __dbt__cte__int_loan_milestones
),
cust_asof as (
    select l.loan_id, d.customer_key,
           row_number() over (partition by l.loan_id order by d.valid_from desc) as rn
    from l
    join "fazz_dwh"."main_warehouse"."dim_customer" d
      on d.customer_id = l.borrower_customer_id
     and d.valid_from <= l.requested_at
     and d.valid_to   >  l.requested_at
),
cust_earliest as (   -- late-arriving dimension: loan requested before the first customer version
    select l.loan_id, d.customer_key,
           row_number() over (partition by l.loan_id order by d.valid_from asc) as rn
    from l
    join "fazz_dwh"."main_warehouse"."dim_customer" d on d.customer_id = l.borrower_customer_id
),
lh as (
    select * from "fazz_dwh"."main_staging"."stg_loanhub_loan"
),
dsb as (
    select loan_id, bank_id, disbursement_method, disbursement_status,
           row_number() over (partition by loan_id order by disbursed_at desc) as rn
    from "fazz_dwh"."main_staging"."stg_disbursement"
),
ins as (
    select loan_id, premium_amount, insurance_vendor, insurance_status from "fazz_dwh"."main_staging"."stg_insurance"
),
fnd as (
    select loan_id,
           count(*)                 as lender_count,
           sum(committed_amount)    as funded_amount_total,
           sum(fund_ratio)          as fund_ratio_total
    from "fazz_dwh"."main_staging"."stg_fund"
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
    from "fazz_dwh"."main_staging"."stg_repayment_schedule"
    group by loan_id
),
pay as (
    select loan_id,
           sum(allocated_amount)    as paid_amount_total,
           sum(allocated_principal) as paid_principal_total,
           sum(allocated_interest)  as paid_interest_total,
           max(paid_date)           as last_paid_date,
           count(distinct transfer_id) as transfer_count
    from __dbt__cte__int_repayment_allocation
    group by loan_id
)
select
    l.loan_id,
    l.borrower_customer_id,
    coalesce(ca.customer_key, ce.customer_key, 'UNKNOWN#1') as borrower_customer_key,
    l.loan_type_id,
    coalesce(lh.partner_id, 'DIRECT')  as partner_id,
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
         then cast((l.nominal_request - l.nominal_loan) as float) / cast(l.nominal_request as float)
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
    
        (date_diff('day', ms.requested_at::timestamp, ms.approved_at::timestamp ))
      as days_request_to_approval,
    
        (date_diff('day', ms.approved_at::timestamp, ms.disbursed_at::timestamp ))
      as days_approval_to_disbursement,
    
        (date_diff('day', ms.requested_at::timestamp, ms.disbursed_at::timestamp ))
      as days_request_to_disbursement,
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
left join "fazz_dwh"."main_staging"."stg_movement_status" s_hist on s_hist.status_name = ms.current_status_name
left join cust_asof ca  on ca.loan_id = l.loan_id and ca.rn = 1
left join cust_earliest ce on ce.loan_id = l.loan_id and ce.rn = 1
left join lh            on lh.loan_id = l.loan_id
left join dsb           on dsb.loan_id = l.loan_id and dsb.rn = 1
left join ins           on ins.loan_id = l.loan_id
left join fnd           on fnd.loan_id = l.loan_id
left join sch           on sch.loan_id = l.loan_id
left join pay           on pay.loan_id = l.loan_id