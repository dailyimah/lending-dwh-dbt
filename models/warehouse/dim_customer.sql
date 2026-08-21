{{ config(materialized='table', cluster_by=['customer_id']) }}
/*
  dim_customer - SCD Type 2. Grain: one row per customer VERSION.
  Key: customer_key = customer_id#sequence_no (deterministic surrogate).

  Every change in the customer change stream (source record updated, or a new credit
  assessment) opens a new version; staging already drops no-change re-touches.
  In production with current-state-only sources the same result comes from a
  dbt snapshot (strategy: check) over the unified customer model.
*/
with v as (
    select
        *,
        case when is_borrower and is_lender then 'both'
             when is_borrower then 'borrower'
             when is_lender   then 'lender'
             else 'none' end as customer_role
    from {{ ref('int_customer_versions') }}
),
versions as (
    select
        *,
        row_number() over (partition by customer_id order by event_ts)     as sequence_no,
        event_ts                                                           as valid_from,
        lead(event_ts) over (partition by customer_id order by event_ts)   as next_valid_from
    from v
),
-- acquisition channel = channel of the customer's first loan
first_loan as (
    select
        l.borrower_customer_id as customer_id,
        case when lh.loan_id is not null then 'partner' else 'direct' end as origination_channel,
        row_number() over (partition by l.borrower_customer_id order by l.requested_at, l.loan_id) as rn
    from {{ ref('stg_loan') }} l
    left join {{ ref('stg_loanhub_loan') }} lh on lh.loan_id = l.loan_id
)
select
    {{ dbt.concat(["v.customer_id", "'#'", "cast(v.sequence_no as " ~ dbt.type_string() ~ ")"]) }} as customer_key,
    v.customer_id,
    v.sequence_no,
    v.entity_type,
    v.customer_name,
    v.email,
    v.phone_number,
    v.country_id, v.province_id, v.city_id, v.district_id,
    v.is_borrower,
    v.is_lender,
    v.customer_role,
    case when v.is_lender and v.entity_type = 'company'    then 'institutional'
         when v.is_lender and v.entity_type = 'individual' then 'retail' end as lender_type,
    fl.origination_channel,
    v.identity_card_type,
    v.credit_score,
    v.assessed_grade                                        as credit_grade,
    v.founded_date,
    v.pic_name,
    v.nib_number,
    v.source_created_at,
    v.source_updated_at,
    v.valid_from,
    coalesce(v.next_valid_from, cast('9999-12-31' as timestamp)) as valid_to,
    v.next_valid_from is null                               as is_current
from versions v
left join first_loan fl on fl.customer_id = v.customer_id and fl.rn = 1

union all

-- member for orphaned / unknown foreign keys
select
    'UNKNOWN#1', 'UNKNOWN', 1, 'unknown', 'Unknown customer', null, null,
    null, null, null, null,
    false, false, 'none', null, null, null, null, null,
    null, null, null,
    cast('1900-01-01' as timestamp), cast('1900-01-01' as timestamp),
    cast('1900-01-01' as timestamp), cast('9999-12-31' as timestamp), true
