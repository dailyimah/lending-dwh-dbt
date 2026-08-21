{{ config(
    materialized='table',
    partition_by=bq_partition('due_date', 'month'),
    cluster_by=['loan_id']
) }}
/*
  fact_repayment_schedule - TRANSACTIONAL (immutable). Grain: one expected installment of one loan.
  Lump-sum loans have exactly one row. Allocated payments are rolled up per installment;
  payment-level detail lives in fact_repayment.
*/
with s as (
    select * from {{ ref('stg_repayment_schedule') }}
),
fl as (
    select loan_id, borrower_customer_key, loan_type_id, partner_id, repayment_mode, grade, disbursement_cohort
    from {{ ref('fact_loan') }}
),
alloc as (
    select schedule_id,
           sum(allocated_amount)    as paid_amount,
           sum(allocated_principal) as paid_principal,
           sum(allocated_interest)  as paid_interest
    from {{ ref('int_repayment_allocation') }}
    where schedule_id is not null
    group by schedule_id
),
-- date on which cumulative allocations reached the due amount
fully_paid as (
    select schedule_id, min(paid_date) as fully_paid_date
    from (
        select schedule_id, paid_date, due_amount,
               sum(allocated_amount) over (partition by schedule_id order by paid_at, repayment_id
                                           rows between unbounded preceding and current row) as cum_alloc
        from {{ ref('int_repayment_allocation') }}
        where schedule_id is not null
    ) x
    where cum_alloc >= due_amount - {{ var('amount_tolerance') }}
    group by schedule_id
)
select
    s.schedule_id,
    s.loan_id,
    s.installment_no,
    coalesce(fl.borrower_customer_key, 'UNKNOWN#1')             as borrower_customer_key,
    fl.loan_type_id,
    fl.partner_id,
    fl.repayment_mode,
    fl.grade,
    fl.disbursement_cohort,
    s.due_date,
    s.due_principal,
    s.due_interest,
    s.due_amount,
    coalesce(a.paid_amount, 0)                                  as paid_amount,
    coalesce(a.paid_principal, 0)                               as paid_principal,
    coalesce(a.paid_interest, 0)                                as paid_interest,
    greatest(s.due_amount - coalesce(a.paid_amount, 0), 0)      as remaining_amount,
    fp.fully_paid_date,
    fp.fully_paid_date is not null                              as is_fully_paid,
    {{ dbt.datediff('s.due_date', 'fp.fully_paid_date', 'day') }} as days_late_to_full_payment
from s
left join fl on fl.loan_id = s.loan_id
left join alloc a on a.schedule_id = s.schedule_id
left join fully_paid fp on fp.schedule_id = s.schedule_id
