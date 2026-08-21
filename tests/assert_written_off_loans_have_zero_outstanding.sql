-- DQ: once a loan is written off its outstanding principal is zero and the residual is the written-off amount.
select loan_id, outstanding_principal, written_off_amount
from {{ ref('fact_loan') }}
where current_status_name = 'written_off'
  and (outstanding_principal <> 0 or written_off_amount <= 0)
