
/*
  mart_credit_score_by_segment - average credit score per customer segment (task mart 4a),
  with portfolio context per segment. LONG format: one row per (segment_type, segment_value),
  so any single axis or the combined entityxchannel view is a filter away.
  Segments use only source-grounded attributes (no invented tiers).
*/

with base as (
    select * from "fazz_dwh"."main_marts"."mart_customer_360"
)

select
    'entity_type'                                              as segment_type,
    entity_type                                                as segment_value,
    count(*)                                                      as customers,
    sum(case when credit_score is not null then 1 else 0 end)     as customers_scored,
    avg(credit_score)                                             as avg_credit_score,
    min(credit_score)                                             as min_credit_score,
    max(credit_score)                                             as max_credit_score,
    stddev(credit_score)                                          as stddev_credit_score,
    sum(case when loans_disbursed_count > 0 then 1 else 0 end)    as borrowers_with_disbursement,
    sum(total_disbursed_amount)                                   as total_disbursed_amount,
    sum(current_outstanding_principal)                            as current_outstanding_principal,
    avg(max_dpd_ever)                                             as avg_max_dpd_ever,
    avg(case when ever_npl_90 then 1.0 else 0.0 end)              as share_ever_npl_90,
    avg(on_time_repayment_rate)                                   as avg_on_time_repayment_rate,
    max(as_of_date)                                               as as_of_date
from base
group by 1, 2
union all

select
    'customer_role'                                              as segment_type,
    customer_role                                                as segment_value,
    count(*)                                                      as customers,
    sum(case when credit_score is not null then 1 else 0 end)     as customers_scored,
    avg(credit_score)                                             as avg_credit_score,
    min(credit_score)                                             as min_credit_score,
    max(credit_score)                                             as max_credit_score,
    stddev(credit_score)                                          as stddev_credit_score,
    sum(case when loans_disbursed_count > 0 then 1 else 0 end)    as borrowers_with_disbursement,
    sum(total_disbursed_amount)                                   as total_disbursed_amount,
    sum(current_outstanding_principal)                            as current_outstanding_principal,
    avg(max_dpd_ever)                                             as avg_max_dpd_ever,
    avg(case when ever_npl_90 then 1.0 else 0.0 end)              as share_ever_npl_90,
    avg(on_time_repayment_rate)                                   as avg_on_time_repayment_rate,
    max(as_of_date)                                               as as_of_date
from base
group by 1, 2
union all

select
    'origination_channel'                                              as segment_type,
    coalesce(origination_channel, 'no_loan')                                                as segment_value,
    count(*)                                                      as customers,
    sum(case when credit_score is not null then 1 else 0 end)     as customers_scored,
    avg(credit_score)                                             as avg_credit_score,
    min(credit_score)                                             as min_credit_score,
    max(credit_score)                                             as max_credit_score,
    stddev(credit_score)                                          as stddev_credit_score,
    sum(case when loans_disbursed_count > 0 then 1 else 0 end)    as borrowers_with_disbursement,
    sum(total_disbursed_amount)                                   as total_disbursed_amount,
    sum(current_outstanding_principal)                            as current_outstanding_principal,
    avg(max_dpd_ever)                                             as avg_max_dpd_ever,
    avg(case when ever_npl_90 then 1.0 else 0.0 end)              as share_ever_npl_90,
    avg(on_time_repayment_rate)                                   as avg_on_time_repayment_rate,
    max(as_of_date)                                               as as_of_date
from base
group by 1, 2
union all

select
    'lender_type'                                              as segment_type,
    coalesce(lender_type, 'not_lender')                                                as segment_value,
    count(*)                                                      as customers,
    sum(case when credit_score is not null then 1 else 0 end)     as customers_scored,
    avg(credit_score)                                             as avg_credit_score,
    min(credit_score)                                             as min_credit_score,
    max(credit_score)                                             as max_credit_score,
    stddev(credit_score)                                          as stddev_credit_score,
    sum(case when loans_disbursed_count > 0 then 1 else 0 end)    as borrowers_with_disbursement,
    sum(total_disbursed_amount)                                   as total_disbursed_amount,
    sum(current_outstanding_principal)                            as current_outstanding_principal,
    avg(max_dpd_ever)                                             as avg_max_dpd_ever,
    avg(case when ever_npl_90 then 1.0 else 0.0 end)              as share_ever_npl_90,
    avg(on_time_repayment_rate)                                   as avg_on_time_repayment_rate,
    max(as_of_date)                                               as as_of_date
from base
group by 1, 2
union all

select
    'province'                                              as segment_type,
    coalesce(province_id, 'unknown')                                                as segment_value,
    count(*)                                                      as customers,
    sum(case when credit_score is not null then 1 else 0 end)     as customers_scored,
    avg(credit_score)                                             as avg_credit_score,
    min(credit_score)                                             as min_credit_score,
    max(credit_score)                                             as max_credit_score,
    stddev(credit_score)                                          as stddev_credit_score,
    sum(case when loans_disbursed_count > 0 then 1 else 0 end)    as borrowers_with_disbursement,
    sum(total_disbursed_amount)                                   as total_disbursed_amount,
    sum(current_outstanding_principal)                            as current_outstanding_principal,
    avg(max_dpd_ever)                                             as avg_max_dpd_ever,
    avg(case when ever_npl_90 then 1.0 else 0.0 end)              as share_ever_npl_90,
    avg(on_time_repayment_rate)                                   as avg_on_time_repayment_rate,
    max(as_of_date)                                               as as_of_date
from base
group by 1, 2
union all

select
    'credit_grade'                                              as segment_type,
    coalesce(credit_grade, 'unscored')                                                as segment_value,
    count(*)                                                      as customers,
    sum(case when credit_score is not null then 1 else 0 end)     as customers_scored,
    avg(credit_score)                                             as avg_credit_score,
    min(credit_score)                                             as min_credit_score,
    max(credit_score)                                             as max_credit_score,
    stddev(credit_score)                                          as stddev_credit_score,
    sum(case when loans_disbursed_count > 0 then 1 else 0 end)    as borrowers_with_disbursement,
    sum(total_disbursed_amount)                                   as total_disbursed_amount,
    sum(current_outstanding_principal)                            as current_outstanding_principal,
    avg(max_dpd_ever)                                             as avg_max_dpd_ever,
    avg(case when ever_npl_90 then 1.0 else 0.0 end)              as share_ever_npl_90,
    avg(on_time_repayment_rate)                                   as avg_on_time_repayment_rate,
    max(as_of_date)                                               as as_of_date
from base
group by 1, 2
union all

select
    'repeat_borrower'                                              as segment_type,
    case when is_repeat_borrower then 'repeat' else 'first_time_or_none' end                                                as segment_value,
    count(*)                                                      as customers,
    sum(case when credit_score is not null then 1 else 0 end)     as customers_scored,
    avg(credit_score)                                             as avg_credit_score,
    min(credit_score)                                             as min_credit_score,
    max(credit_score)                                             as max_credit_score,
    stddev(credit_score)                                          as stddev_credit_score,
    sum(case when loans_disbursed_count > 0 then 1 else 0 end)    as borrowers_with_disbursement,
    sum(total_disbursed_amount)                                   as total_disbursed_amount,
    sum(current_outstanding_principal)                            as current_outstanding_principal,
    avg(max_dpd_ever)                                             as avg_max_dpd_ever,
    avg(case when ever_npl_90 then 1.0 else 0.0 end)              as share_ever_npl_90,
    avg(on_time_repayment_rate)                                   as avg_on_time_repayment_rate,
    max(as_of_date)                                               as as_of_date
from base
group by 1, 2
union all

select
    'entity_x_channel'                                              as segment_type,
    entity_type || ' / ' || coalesce(origination_channel, 'no_loan')                                                as segment_value,
    count(*)                                                      as customers,
    sum(case when credit_score is not null then 1 else 0 end)     as customers_scored,
    avg(credit_score)                                             as avg_credit_score,
    min(credit_score)                                             as min_credit_score,
    max(credit_score)                                             as max_credit_score,
    stddev(credit_score)                                          as stddev_credit_score,
    sum(case when loans_disbursed_count > 0 then 1 else 0 end)    as borrowers_with_disbursement,
    sum(total_disbursed_amount)                                   as total_disbursed_amount,
    sum(current_outstanding_principal)                            as current_outstanding_principal,
    avg(max_dpd_ever)                                             as avg_max_dpd_ever,
    avg(case when ever_npl_90 then 1.0 else 0.0 end)              as share_ever_npl_90,
    avg(on_time_repayment_rate)                                   as avg_on_time_repayment_rate,
    max(as_of_date)                                               as as_of_date
from base
group by 1, 2

