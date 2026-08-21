
/*
  fact_repayment_schedule - TRANSACTIONAL (immutable). Grain: one expected installment of one loan.
  Lump-sum loans have exactly one row. Allocated-payment roll-ups are attached for convenience;
  the payment-level detail lives in fact_repayment.
*/
with  __dbt__cte__int_repayment_allocation as (

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
), s as (
    select * from "fazz_dwh"."main_staging"."stg_repayment_schedule"
),
fl as (
    select loan_id, borrower_customer_key, loan_type_id, partner_id, repayment_mode, grade, disbursement_cohort
    from "fazz_dwh"."main_warehouse"."fact_loan"
),
alloc as (
    select
        schedule_id,
        sum(allocated_amount)    as paid_amount,
        sum(allocated_principal) as paid_principal,
        sum(allocated_interest)  as paid_interest,
        min(paid_date)           as first_paid_date,
        count(*)                 as allocation_count
    from __dbt__cte__int_repayment_allocation
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
        from __dbt__cte__int_repayment_allocation
        where schedule_id is not null
    ) x
    where cum_alloc >= due_amount - 1
    group by schedule_id
)
select
    s.schedule_id,
    s.loan_id,
    s.installment_no,
    fl.borrower_customer_key,
    fl.loan_type_id,
    fl.partner_id,
    fl.repayment_mode,
    fl.grade,
    fl.disbursement_cohort,
    s.due_date,
    cast(extract(year from s.due_date) * 100 + extract(month from s.due_date) as integer) as due_year_month,
    s.due_principal,
    s.due_interest,
    s.due_amount,
    coalesce(a.paid_amount, 0)                                  as paid_amount,
    coalesce(a.paid_principal, 0)                               as paid_principal,
    coalesce(a.paid_interest, 0)                                as paid_interest,
    greatest(s.due_amount - coalesce(a.paid_amount, 0), 0)      as remaining_amount,
    coalesce(a.allocation_count, 0)                             as allocation_count,
    a.first_paid_date,
    fp.fully_paid_date,
    fp.fully_paid_date is not null                              as is_fully_paid,
    coalesce(a.allocation_count, 0) > 1                         as is_paid_in_parts,
    
        (date_diff('day', s.due_date::timestamp, fp.fully_paid_date::timestamp ))
     as days_late_to_full_payment,
    case when fp.fully_paid_date is null and s.due_date < cast('2026-08-21' as date)
         then 
        (date_diff('day', s.due_date::timestamp, cast('2026-08-21' as date)::timestamp ))
     else 0 end as days_past_due_as_of
from s
left join fl on fl.loan_id = s.loan_id
left join alloc a on a.schedule_id = s.schedule_id
left join fully_paid fp on fp.schedule_id = s.schedule_id