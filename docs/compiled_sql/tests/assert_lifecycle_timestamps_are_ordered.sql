
-- DQ: lifecycle milestones must be chronologically ordered.
select loan_id, requested_at, approved_at, disbursed_at, closed_at
from "fazz_dwh"."main_warehouse"."fact_loan"
where (approved_at  is not null and approved_at  < requested_at)
   or (disbursed_at is not null and disbursed_at < coalesce(approved_at, requested_at))
   or (closed_at    is not null and closed_at    < coalesce(disbursed_at, approved_at, requested_at))