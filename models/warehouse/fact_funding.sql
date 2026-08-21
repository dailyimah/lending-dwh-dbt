{{ config(
    materialized='table',
    partition_by=bq_partition('funded_date', 'month'),
    cluster_by=['lender_customer_id']
) }}
/*
  fact_funding - TRANSACTIONAL. Grain: one lender's funding commitment to one loan (fund table).
  fund_record is rolled up (settled/signed amounts). lender_customer_key is the dim_customer
  version valid at funding time. Exposure = lender's share of the loan's current outstanding principal.
*/
with f as (
    select * from {{ ref('stg_fund') }}
),
fr as (
    select fund_id,
           count(*)                                               as record_count,
           sum(amount)                                            as recorded_amount,
           sum(case when is_settled then amount else 0 end)       as settled_amount,
           sum(case when is_signed  then amount else 0 end)       as signed_amount,
           min(case when is_signed then 1 else 0 end) = 1         as is_fully_signed
    from {{ ref('stg_fund_record') }}
    group by fund_id
),
lender_asof as (
    select f.fund_id, d.customer_key,
           row_number() over (partition by f.fund_id order by d.valid_from desc) as rn
    from f
    join {{ ref('dim_customer') }} d
      on d.customer_id = f.lender_customer_id
     and d.valid_from <= f.funded_at and d.valid_to > f.funded_at
),
lender_earliest as (
    select f.fund_id, d.customer_key,
           row_number() over (partition by f.fund_id order by d.valid_from asc) as rn
    from f
    join {{ ref('dim_customer') }} d on d.customer_id = f.lender_customer_id
),
fl as (
    select loan_id, borrower_customer_key, loan_type_id, partner_id, grade, nominal_loan,
           current_status_name, outstanding_principal, disbursed_date, disbursement_cohort
    from {{ ref('fact_loan') }}
)
select
    f.fund_id,
    f.loan_id,
    f.lender_customer_id,
    coalesce(la.customer_key, le.customer_key, '{{ var("unknown_member_key") }}#1') as lender_customer_key,
    fl.borrower_customer_key,
    fl.loan_type_id,
    fl.partner_id,
    fl.grade,
    fl.disbursement_cohort,
    f.funded_at,
    cast(f.funded_at as date)                                   as funded_date,
    f.fund_status,
    f.committed_amount,
    f.fund_ratio,
    case when fl.nominal_loan > 0
         then cast(f.committed_amount as {{ dbt.type_float() }}) / cast(fl.nominal_loan as {{ dbt.type_float() }}) end as share_of_loan,
    coalesce(fr.record_count, 0)                                as record_count,
    coalesce(fr.recorded_amount, 0)                             as recorded_amount,
    coalesce(fr.settled_amount, 0)                              as settled_amount,
    coalesce(fr.signed_amount, 0)                               as signed_amount,
    coalesce(fr.settled_amount, 0) >= f.committed_amount - {{ var('amount_tolerance') }} as is_fully_settled,
    coalesce(fr.is_fully_signed, false)                         as is_fully_signed,
    f.committed_amount - coalesce(fr.settled_amount, 0)         as unsettled_amount,
    fl.current_status_name                                      as loan_status_name,
    coalesce(fl.outstanding_principal, 0) * f.fund_ratio        as current_exposure_amount,
    fl.current_status_name = 'disbursed'                        as is_loan_active,
    f.source_updated_at
from f
left join fr on fr.fund_id = f.fund_id
left join lender_asof la on la.fund_id = f.fund_id and la.rn = 1
left join lender_earliest le on le.fund_id = f.fund_id and le.rn = 1
left join fl on fl.loan_id = f.loan_id
