{{ config(
    materialized='table',
    partition_by=bq_partition('funded_date', 'month'),
    cluster_by=['lender_customer_id']
) }}
/*
  fact_funding - TRANSACTIONAL. Grain: one lender's funding commitment to one loan (fund table);
  fund_record rolled up into settled amount. lender_customer_key = dim_customer version valid at
  funding time. Exposure = lender's share of the loan's current outstanding principal.
*/
with f as (
    select * from {{ ref('stg_fund') }}
),
fr as (
    select fund_id, sum(case when is_settled then amount else 0 end) as settled_amount
    from {{ ref('stg_fund_record') }}
    group by fund_id
),
lender as (
    select f.fund_id, d.customer_key,
           row_number() over (
               partition by f.fund_id
               order by case when d.valid_from <= f.funded_at then 0 else 1 end,
                        case when d.valid_from <= f.funded_at then d.valid_from end desc,
                        d.valid_from asc
           ) as rn
    from f
    join {{ ref('dim_customer') }} d on d.customer_id = f.lender_customer_id
),
fl as (
    select loan_id, borrower_customer_key, loan_type_id, partner_id, grade, disbursement_cohort,
           current_status_name, outstanding_principal
    from {{ ref('fact_loan') }}
)
select
    f.fund_id,
    f.loan_id,
    f.lender_customer_id,
    coalesce(le.customer_key, 'UNKNOWN#1')                      as lender_customer_key,
    coalesce(fl.borrower_customer_key, 'UNKNOWN#1')             as borrower_customer_key,
    fl.loan_type_id,
    fl.partner_id,
    fl.grade,
    fl.disbursement_cohort,
    f.funded_at,
    cast(f.funded_at as date)                                   as funded_date,
    f.fund_status,
    f.committed_amount,
    f.fund_ratio,
    coalesce(fr.settled_amount, 0)                              as settled_amount,
    coalesce(fr.settled_amount, 0) >= f.committed_amount - {{ var('amount_tolerance') }} as is_fully_settled,
    fl.current_status_name                                      as loan_status_name,
    fl.current_status_name = 'disbursed'                        as is_loan_active,
    coalesce(fl.outstanding_principal, 0) * f.fund_ratio        as current_exposure_amount,
    f.source_updated_at
from f
left join fr     on fr.fund_id = f.fund_id
left join lender le on le.fund_id = f.fund_id and le.rn = 1
left join fl     on fl.loan_id = f.loan_id
