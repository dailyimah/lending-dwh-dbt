{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key=['snapshot_date', 'loan_id'],
    partition_by=bq_partition('snapshot_date', 'day'),
    cluster_by=['loan_id'],
    on_schema_change='sync_all_columns'
) }}
/*
  fact_loan_daily_snapshot - PERIODIC SNAPSHOT. Grain: one ACTIVE loan per calendar day,
  from disbursement date through the closing day (inclusive; the last row carries the terminal
  status). Outstanding principal, overdue amount, DPD and OJK bucket as of each day.
  DPD = days since the due date of the oldest installment not fully covered by payments
  received on or before that day (payments allocated oldest-due-first).
  Incremental by snapshot_date: each run recomputes only days after the last loaded day
  (delete+insert on the partition keys keeps reruns idempotent).
*/
with loans as (
    select loan_id, borrower_customer_key, loan_type_id, partner_id, grade, repayment_mode,
           nominal_loan, disbursed_date, closed_date, repaid_at, written_off_at, disbursement_cohort
    from {{ ref('fact_loan') }}
    where disbursed_date is not null
),
days as (
    select date_day from {{ ref('dim_date') }}
    where date_day <= {{ as_of_date() }}
    {% if is_incremental() %}
      and date_day > (select coalesce(max(snapshot_date), cast('1900-01-01' as date)) from {{ this }})
    {% endif %}
),
spine as (
    select d.date_day as snapshot_date, l.*
    from loans l
    join days d
      on d.date_day >= l.disbursed_date
     and d.date_day <= least(coalesce(l.closed_date, {{ as_of_date() }}), {{ as_of_date() }})
),
sched as (
    select loan_id, installment_no, due_date, due_amount, due_principal,
           sum(due_amount) over (partition by loan_id order by installment_no
                                 rows between unbounded preceding and current row) as cum_due_through
    from {{ ref('stg_repayment_schedule') }}
),
alloc as (
    select loan_id, paid_date, allocated_amount, allocated_principal
    from {{ ref('int_repayment_allocation') }}
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
           min(case when sc.cum_due_through > p.paid_amount_to_date + {{ var('amount_tolerance') }}
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
             then {{ dbt.datediff('d.oldest_unpaid_due_date', 's.snapshot_date', 'day') }} else 0 end as days_past_due,
        {{ dbt.datediff('s.disbursed_date', 's.snapshot_date', 'day') }}    as days_since_disbursement
    from spine s
    join paid_asof p on p.snapshot_date = s.snapshot_date and p.loan_id = s.loan_id
    join due_asof  d on d.snapshot_date = s.snapshot_date and d.loan_id = s.loan_id
)
select
    *,
    {{ dpd_bucket('days_past_due') }}                                       as dpd_bucket,
    {{ dpd_bucket_order('days_past_due') }}                                 as dpd_bucket_order,
    days_past_due > 0                                                       as is_delinquent,
    days_past_due > {{ var('tkb_threshold_days') }}                         as is_npl_90,    -- beyond the TKB90 line
    status_name = 'disbursed'                                               as is_active
from calc
