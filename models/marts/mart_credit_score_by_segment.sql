{{ config(materialized='table') }}
/*
  mart_credit_score_by_segment - average credit score per customer segment (task mart 4a),
  with realised-risk context. LONG format: one row per (segment_type, segment_value).
  Segments come from source-present customer attributes (channel is derived from loanhub_loan).
*/
{% set segments = {
    'entity_type':         'entity_type',
    'customer_role':       'customer_role',
    'origination_channel': "coalesce(origination_channel, 'no_loan')",
    'province':            "coalesce(province_id, 'unknown')"
} %}
{% for seg_name, seg_expr in segments.items() %}
select
    '{{ seg_name }}'                                           as segment_type,
    {{ seg_expr }}                                             as segment_value,
    count(*)                                                   as customers,
    sum(case when credit_score is not null then 1 else 0 end)  as customers_scored,
    avg(credit_score)                                          as avg_credit_score,
    sum(case when loans_disbursed_count > 0 then 1 else 0 end) as borrowers_with_disbursement,
    sum(current_outstanding_principal)                         as current_outstanding_principal,
    avg(case when ever_npl_90 then 1.0 else 0.0 end)           as share_ever_npl_90
from {{ ref('mart_customer_360') }}
group by 1, 2
{% if not loop.last %}union all{% endif %}
{% endfor %}
