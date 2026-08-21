
-- DQ: a loan that reached 'disbursed' must have a disbursement record.
select loan_id, disbursed_at
from "fazz_dwh"."main_warehouse"."fact_loan"
where disbursed_at is not null
  and disbursement_bank_id is null