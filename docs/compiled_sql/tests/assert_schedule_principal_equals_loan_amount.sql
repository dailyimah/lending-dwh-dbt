
-- DQ: the repayment schedule's total principal must equal the approved loan amount.
select loan_id, nominal_loan, scheduled_principal_total
from "fazz_dwh"."main_warehouse"."fact_loan"
where disbursed_at is not null
  and abs(coalesce(scheduled_principal_total, 0) - nominal_loan) > 1