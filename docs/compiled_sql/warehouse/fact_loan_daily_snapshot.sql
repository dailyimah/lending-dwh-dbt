
/*
  fact_loan_daily_snapshot - PERIODIC SNAPSHOT. Grain: one ACTIVE loan per calendar day,
  from disbursement date through the closing day (inclusive; the last row carries the terminal
  status). Outstanding principal, overdue amount, DPD and OJK bucket as of each day.
  DPD = days since the due date of the oldest installment not fully covered by payments
  received on or before that day (payments allocated oldest-due-first).
  Incremental by snapshot_date: each run recomputes only days after the last loaded day
  (delete+insert on the partition keys keeps reruns idempotent).
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
), loans as (
    select loan_id, borrower_customer_key, loan_type_id, partner_id, grade, repayment_mode,
           nominal_loan, disbursed_date, closed_date, repaid_at, written_off_at, disbursement_cohort
    from "fazz_dwh"."main_warehouse"."fact_loan"
    where disbursed_date is not null
),
days as (
    select date_day from "fazz_dwh"."main_warehouse"."dim_date"
    where date_day <= cast('2026-08-21' as date)
    
      and date_day > (select coalesce(max(snapshot_date), cast('1900-01-01' as date)) from "fazz_dwh"."main_warehouse"."fact_loan_daily_snapshot")
    
),
spine as (
    select d.date_day as snapshot_date, l.*
    from loans l
    join days d
      on d.date_day >= l.disbursed_date
     and d.date_day <= least(coalesce(l.closed_date, cast('2026-08-21' as date)), cast('2026-08-21' as date))
),
sched as (
    select loan_id, installment_no, due_date, due_amount, due_principal,
           sum(due_amount) over (partition by loan_id order by installment_no
                                 rows between unbounded preceding and current row) as cum_due_through
    from "fazz_dwh"."main_staging"."stg_repayment_schedule"
),
alloc as (
    select loan_id, paid_date, allocated_amount, allocated_principal
    from __dbt__cte__int_repayment_allocation
),
-- payments received on or before each snapshot day
paid_asof as (
    select s.snapshot_date, s.loan_id,
           coalesce(sum(a.allocated_amount), 0)    as paid_amount_to_date,
           coalesce(sum(a.allocated_principal), 0) as paid_principal_to_date
    from spine s
    left join alloc a on a.loan_id = s.loan_id and a.paid_date <= s.snapshot_date
    group by s.snapshot_date, s.loan_id
),
-- installments due on or before each day; oldest one not yet covered drives DPD
due_asof as (
    select s.snapshot_date, s.loan_id,
           coalesce(sum(sc.due_amount), 0) as due_amount_to_date,
           min(case when sc.cum_due_through > p.paid_amount_to_date + 1
                    then sc.due_date end)  as oldest_unpaid_due_date
    from spine s
    join paid_asof p on p.snapshot_date = s.snapshot_date and p.loan_id = s.loan_id
    left join sched sc on sc.loan_id = s.loan_id and sc.due_date <= s.snapshot_date
    group by s.snapshot_date, s.loan_id
),
calc as (
    select
        s.snapshot_date,
        s.loan_id,
        s.borrower_customer_key,
        s.loan_type_id,
        s.partner_id,
        s.grade,
        s.repayment_mode,
        s.disbursement_cohort,
        case when s.written_off_at is not null and cast(s.written_off_at as date) <= s.snapshot_date then 'written_off'
             when s.repaid_at      is not null and cast(s.repaid_at      as date) <= s.snapshot_date then 'repaid'
             else 'disbursed' end                                            as status_name,
        s.snapshot_date = s.closed_date                                     as is_closing_day,
        s.nominal_loan,
        greatest(s.nominal_loan - p.paid_principal_to_date, 0)              as outstanding_principal,
        p.paid_amount_to_date,
        d.due_amount_to_date,
        greatest(d.due_amount_to_date - p.paid_amount_to_date, 0)           as overdue_amount,
        case when d.oldest_unpaid_due_date is not null and d.oldest_unpaid_due_date < s.snapshot_date
             then 
        (date_diff('day', d.oldest_unpaid_due_date::timestamp, s.snapshot_date::timestamp ))
     else 0 end as days_past_due,
        
        (date_diff('day', s.disbursed_date::timestamp, s.snapshot_date::timestamp ))
        as days_since_disbursement
    from spine s
    join paid_asof p on p.snapshot_date = s.snapshot_date and p.loan_id = s.loan_id
    join due_asof  d on d.snapshot_date = s.snapshot_date and d.loan_id = s.loan_id
)
select
    *,
    case
  when days_past_due is null or days_past_due < 1 then 'current'
  when days_past_due < 31 then '1-30'
  when days_past_due < 61 then '31-60'
  when days_past_due < 91 then '61-90'
  else '90+'
end                                       as dpd_bucket,
    case
  when days_past_due is null or days_past_due < 1 then 0
  when days_past_due < 31 then 1
  when days_past_due < 61 then 2
  when days_past_due < 91 then 3
  else 4
end                                 as dpd_bucket_order,
    days_past_due > 0                                                       as is_delinquent,
    days_past_due > 90                         as is_npl_90,    -- beyond the TKB90 line
    status_name = 'disbursed'                                               as is_active
from calc