
/* dim_loan_type - loan products. Natural key: loan_type_id. Static lookup, no SCD. */
with observed as (
    select distinct loan_type_id from "fazz_dwh"."main_staging"."stg_loan"
)
select
    o.loan_type_id,
    coalesce(r.loan_type_name,  'unmapped')  as loan_type_name,
    coalesce(r.loan_type_group, 'unmapped')  as loan_type_group
from observed o
left join "fazz_dwh"."main_raw"."ref_loan_type" r on r.loan_type_id = o.loan_type_id
union all
select 'UNKNOWN', 'unknown', 'unknown'