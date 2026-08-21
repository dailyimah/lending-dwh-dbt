{{ config(severity='warn') }}
-- DQ: payments beyond the scheduled total indicate a schedule or source problem.
select loan_id, transfer_id, allocated_amount
from {{ ref('fact_repayment') }}
where is_overpayment
