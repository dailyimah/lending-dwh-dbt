{{ config(
    materialized='table',
    partition_by=bq_partition('disbursed_date', 'month'),
    cluster_by=['loan_type_id', 'borrower_customer_id']
) }}
/*
  fact_loan - ACCUMULATING SNAPSHOT. Grain: one row per loan, updated as milestones occur.
  Lifecycle milestones, channel, funding/insurance roll-ups, repayment totals, outstanding principal.
  borrower_customer_key = dim_customer version valid when the loan was requested.
*/
with l as (
    select * from {{ ref('stg_loan') }}
),
ms as (
    select * from {{ ref('int_loan_milestones') }}
),
-- version valid at request time; if the loan predates the first version, the earliest version
cust as (
    select l.loan_id, d.customer_key,
           row_number() over (
               partition by l.loan_id
               order by case when d.valid_from <= l.requested_at then 0 else 1 end,
                        case when d.valid_from <= l.requested_at then d.valid_from end desc,
                        d.valid_from asc
           ) as rn
    from l
    join {{ ref('dim_customer') }} d on d.customer_id = l.borrower_customer_id
),
lh as (
    select loan_id, partner_id from {{ ref('stg_loanhub_loan') }}
),
dsb as (
    select loan_id, bank_id,
           row_number() over (partition by loan_id order by disbursed_at desc) as rn
    from {{ ref('stg_disbursement') }}
),
ins as (
    select loan_id from {{ ref('stg_insurance') }}
),
fnd as (
    select loan_id, count(*) as lender_count, sum(committed_amount) as funded_amount_total, sum(fund_ratio) as fund_ratio_total
    from {{ ref('stg_fund') }}
    group by loan_id
),
sch as (
    select loan_id, sum(due_principal) as scheduled_principal_total, max(due_date) as maturity_date
    from {{ ref('stg_repayment_schedule') }}
    group by loan_id
),
pay as (
    select loan_id,
           sum(allocated_amount)    as paid_amount_total,
           sum(allocated_principal) as paid_principal_total,
           sum(allocated_interest)  as paid_interest_total
    from {{ ref('int_repayment_allocation') }}
    group by loan_id
),
-- first installment: due date and the day it was fully covered (first payment default)
first_inst as (
    select s.loan_id, s.due_date as first_due_date, s.due_amount as first_due_amount,
           min(case when a.cum_alloc >= s.due_amount - {{ var('amount_tolerance') }} then a.paid_date end) as first_fully_paid_date
    from {{ ref('stg_repayment_schedule') }} s
    left join (
        select schedule_id, paid_date,
               sum(allocated_amount) over (partition by schedule_id order by paid_at, repayment_id
                                           rows between unbounded preceding and current row) as cum_alloc
        from {{ ref('int_repayment_allocation') }}
        where installment_no = 1
    ) a on a.schedule_id = s.schedule_id
    where s.installment_no = 1
    group by s.loan_id, s.due_date, s.due_amount
),
-- borrower attributes as they were when the loan was requested (SCD2 version)
cust_at_request as (
    select c.loan_id, d.credit_score, d.credit_grade as assessed_grade
    from cust c
    join {{ ref('dim_customer') }} d on d.customer_key = c.customer_key
    where c.rn = 1
)
select
    l.loan_id,
    l.borrower_customer_id,
    coalesce(c.customer_key, 'UNKNOWN#1')                       as borrower_customer_key,
    coalesce(l.loan_type_id, 'UNKNOWN')                         as loan_type_id,
    coalesce(lh.partner_id, 'DIRECT')                           as partner_id,
    case when lh.loan_id is not null then 'partner' else 'direct' end as origination_channel,

    -- terms
    l.tenor_months,
    l.repayment_mode,
    l.grade,
    l.nominal_request,
    l.nominal_loan,
    case when l.nominal_request > 0 and l.nominal_loan > 0
         then cast(l.nominal_request - l.nominal_loan as {{ dbt.type_float() }}) / cast(l.nominal_request as {{ dbt.type_float() }})
         end                                                    as approval_haircut_pct,   -- NULL unless approved
    car.credit_score                                            as credit_score_at_request,
    car.assessed_grade                                          as credit_grade_at_request,

    -- status (movement history is the source of truth)
    ms.current_status_name,
    coalesce(ms.current_movement_id, 'UNKNOWN')                 as current_movement_id,
    l.source_movement_id is distinct from ms.current_movement_id as has_status_mismatch,

    -- lifecycle milestones (accumulating snapshot)
    ms.requested_at, ms.approved_at, ms.funding_at, ms.disbursed_at,
    ms.repaid_at, ms.written_off_at, ms.rejected_at, ms.cancelled_at, ms.closed_at,
    cast({{ dbt.dateadd('hour', var('source_utc_offset_hours'), 'ms.disbursed_at') }} as date)   as disbursed_date,    -- business dates in Jakarta time
    cast({{ dbt.dateadd('hour', var('source_utc_offset_hours'), 'ms.closed_at') }} as date)      as closed_date,
    cast(extract(year from cast({{ dbt.dateadd('hour', var('source_utc_offset_hours'), 'ms.disbursed_at') }} as date)) * 100
       + extract(month from cast({{ dbt.dateadd('hour', var('source_utc_offset_hours'), 'ms.disbursed_at') }} as date)) as integer) as disbursement_cohort,
    {{ dbt.datediff('ms.requested_at', 'ms.disbursed_at', 'day') }} as days_request_to_disbursement,

    -- disbursement, insurance, funding roll-ups
    dsb.bank_id                                                 as disbursement_bank_id,
    ins.loan_id is not null                                     as has_insurance,
    coalesce(fnd.lender_count, 0)                               as lender_count,
    coalesce(fnd.funded_amount_total, 0)                        as funded_amount_total,
    fnd.fund_ratio_total,

    -- schedule & repayment roll-ups
    sch.scheduled_principal_total,
    sch.maturity_date,
    coalesce(pay.paid_amount_total, 0)                          as paid_amount_total,
    coalesce(pay.paid_principal_total, 0)                       as paid_principal_total,
    coalesce(pay.paid_interest_total, 0)                        as paid_interest_total,
    -- outstanding is zero once a loan is written off; the residual moves to written_off_amount
    case when ms.written_off_at is not null then 0
         when ms.disbursed_at is not null
         then greatest(l.nominal_loan - coalesce(pay.paid_principal_total, 0), 0) end as outstanding_principal,
    case when ms.written_off_at is not null
         then greatest(l.nominal_loan - coalesce(pay.paid_principal_total, 0), 0) else 0 end as written_off_amount,

    -- first payment default: first installment not covered within 30 days of its due date
    fi.first_due_date,
    fi.first_fully_paid_date,
    case when fi.first_fully_paid_date is not null then {{ dbt.datediff('fi.first_due_date', 'fi.first_fully_paid_date', 'day') }}
         when fi.first_due_date is not null then {{ dbt.datediff('fi.first_due_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} end as first_installment_days_late,
    case when fi.first_due_date is null then null
         when fi.first_fully_paid_date is not null then {{ dbt.datediff('fi.first_due_date', 'fi.first_fully_paid_date', 'day') }} > 30
         else {{ dbt.datediff('fi.first_due_date', "date '" ~ var('as_of_date') ~ "'", 'day') }} > 30 end as is_fpd,

    l.source_updated_at
from l
left join ms   on ms.loan_id = l.loan_id
left join cust c on c.loan_id = l.loan_id and c.rn = 1
left join lh   on lh.loan_id = l.loan_id
left join dsb  on dsb.loan_id = l.loan_id and dsb.rn = 1
left join ins  on ins.loan_id = l.loan_id
left join fnd  on fnd.loan_id = l.loan_id
left join sch  on sch.loan_id = l.loan_id
left join pay  on pay.loan_id = l.loan_id
left join first_inst fi on fi.loan_id = l.loan_id
left join cust_at_request car on car.loan_id = l.loan_id
