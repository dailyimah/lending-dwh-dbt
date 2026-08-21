-- DQ: allocation must neither create nor lose money - per loan, allocated = transferred.
with transfers as (
    select loan_id, sum(paid_amount) as transferred from "fazz_dwh"."main_staging"."stg_repayment" group by loan_id
),
allocated as (
    select loan_id, sum(allocated_amount) as allocated from "fazz_dwh"."main_warehouse"."fact_repayment" group by loan_id
)
select t.loan_id, t.transferred, a.allocated
from transfers t
full outer join allocated a on a.loan_id = t.loan_id
where abs(coalesce(t.transferred, 0) - coalesce(a.allocated, 0)) > 1