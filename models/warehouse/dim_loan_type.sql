{{ config(materialized='table') }}
/* dim_loan_type - loan products. Natural key: loan_type_id. Static lookup. */
select
    o.loan_type_id,
    coalesce(r.loan_type_name,  'unknown') as loan_type_name,
    coalesce(r.loan_type_group, 'unknown') as loan_type_group
from (select distinct loan_type_id from {{ ref('stg_loan') }}) o
left join {{ ref('ref_loan_type') }} r on r.loan_type_id = o.loan_type_id
union all
select 'UNKNOWN', 'unknown', 'unknown'
