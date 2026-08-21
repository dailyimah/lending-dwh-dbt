{{ config(materialized='ephemeral') }}
/*
  int_repayment_allocation - allocates each raw transfer to installments, oldest due first.
  Running total of payments (by paid_at) vs running total of dues (by installment_no):
  the overlap of the two intervals is how much of a payment lands on an installment.
  A final "overflow" interval per loan (installment_no NULL) catches payments beyond the schedule.
  Principal/interest split of an allocation is proportional to the installment's split.
*/
with sched_base as (
    select loan_id, schedule_id, installment_no, due_date, due_principal, due_interest, due_amount
    from {{ ref('stg_repayment_schedule') }}
),
sched as (
    select
        *,
        coalesce(sum(due_amount) over (partition by loan_id order by installment_no
                                       rows between unbounded preceding and 1 preceding), 0) as cum_due_start,
        sum(due_amount) over (partition by loan_id order by installment_no
                              rows between unbounded preceding and current row)              as cum_due_end
    from sched_base
    union all
    select
        loan_id,
        cast(null as {{ dbt.type_string() }}), cast(null as integer), cast(null as date),
        0, 0, 0,
        sum(due_amount), cast(1e18 as {{ dbt.type_numeric() }})
    from sched_base
    group by loan_id
),
paid as (
    select
        loan_id, repayment_id, transfer_id, paid_at, paid_date, payment_channel, paid_amount,
        coalesce(sum(paid_amount) over (partition by loan_id order by paid_at, repayment_id
                                        rows between unbounded preceding and 1 preceding), 0) as cum_paid_start,
        sum(paid_amount) over (partition by loan_id order by paid_at, repayment_id
                               rows between unbounded preceding and current row)               as cum_paid_end
    from {{ ref('stg_repayment') }}
),
overlap as (
    select
        p.loan_id, p.repayment_id, p.transfer_id, p.paid_at, p.paid_date, p.payment_channel, p.paid_amount,
        s.schedule_id, s.installment_no, s.due_date, s.due_principal, s.due_interest, s.due_amount,
        least(p.cum_paid_end, s.cum_due_end) - greatest(p.cum_paid_start, s.cum_due_start) as allocated_amount
    from paid p
    join sched s
      on s.loan_id = p.loan_id
     and least(p.cum_paid_end, s.cum_due_end) > greatest(p.cum_paid_start, s.cum_due_start)
)
select
    *,
    case when due_amount > 0 then allocated_amount * (due_principal / due_amount) else 0 end as allocated_principal,
    case when due_amount > 0 then allocated_amount * (due_interest  / due_amount) else 0 end as allocated_interest
from overlap
