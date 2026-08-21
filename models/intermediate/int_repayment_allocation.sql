{{ config(materialized='ephemeral') }}
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
    from {{ ref('stg_repayment_schedule') }}
),
paid as (
    select
        loan_id, repayment_id, transfer_id, paid_at, paid_date, payment_channel, paid_amount,
        sum(paid_amount) over (partition by loan_id order by paid_at, repayment_id
                               rows between unbounded preceding and 1 preceding) as cum_paid_start,
        sum(paid_amount) over (partition by loan_id order by paid_at, repayment_id
                               rows between unbounded preceding and current row) as cum_paid_end
    from {{ ref('stg_repayment') }}
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
        cast(null as {{ dbt.type_string() }}) as schedule_id,
        cast(null as integer) as installment_no,
        cast(null as date)    as due_date,
        cast(0 as {{ dbt.type_numeric() }}) as due_principal,
        cast(0 as {{ dbt.type_numeric() }}) as due_interest,
        cast(0 as {{ dbt.type_numeric() }}) as due_amount,
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
