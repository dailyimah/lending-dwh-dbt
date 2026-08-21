
-- DQ: payments beyond the scheduled total indicate a schedule or source problem.
select loan_id, transfer_id, allocated_amount
from "fazz_dwh"."main_warehouse"."fact_repayment"
where is_overpayment