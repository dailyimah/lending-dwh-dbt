-- DQ: a loan whose history says repaid must have no remaining amount on any installment.
select s.loan_id, s.installment_no, s.remaining_amount
from {{ ref('fact_repayment_schedule') }} s
join {{ ref('fact_loan') }} l on l.loan_id = s.loan_id
where l.current_status_name = 'repaid'
  and s.remaining_amount > {{ var('amount_tolerance') }}
