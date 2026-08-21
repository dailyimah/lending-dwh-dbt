{{ config(
    materialized='table',
    partition_by=bq_partition('paid_date', 'month'),
    cluster_by=['loan_id']
) }}
/*
  fact_repayment - TRANSACTIONAL (append-only). Grain: one payment APPLIED TO one installment.
  A transfer covering two installments yields two rows; transfer_id preserved so the original
  transfer is reconstructable. installment_no NULL = overpayment beyond the schedule.
*/
with a as (
    select * from {{ ref('int_repayment_allocation') }}
),
fl as (
    select loan_id, borrower_customer_key, loan_type_id, partner_id, repayment_mode, grade
    from {{ ref('fact_loan') }}
)
select
    {{ dbt.concat(["a.repayment_id", "'#'", "coalesce(cast(a.installment_no as " ~ dbt.type_string() ~ "), 'over')"]) }} as repayment_allocation_key,
    a.repayment_id,
    a.transfer_id,
    a.loan_id,
    a.schedule_id,
    a.installment_no,
    fl.borrower_customer_key,
    fl.loan_type_id,
    fl.partner_id,
    fl.repayment_mode,
    fl.grade,
    a.paid_at,
    a.paid_date,
    a.payment_channel,
    a.paid_amount                                               as transfer_amount,
    a.allocated_amount,
    a.allocated_principal,
    a.allocated_interest,
    a.due_date,
    {{ dbt.datediff('a.due_date', 'a.paid_date', 'day') }}      as days_late,          -- negative = early
    a.due_date is not null and a.paid_date > a.due_date         as is_late,
    a.installment_no is null                                    as is_overpayment
from a
left join fl on fl.loan_id = a.loan_id
