{{ config(materialized='table') }}
/*
  dim_partner - origination channel / channeling partners. Natural key: partner_id.
  Includes a DIRECT member (loans with no loanhub mapping) and an UNKNOWN member.
*/
with observed as (
    select distinct partner_id from {{ ref('stg_loanhub_loan') }}
)
select
    o.partner_id,
    coalesce(r.partner_name, 'Unmapped partner') as partner_name,
    coalesce(r.channel_type, 'partner')          as channel_type
from observed o
left join {{ ref('ref_partner') }} r on r.partner_id = o.partner_id
union all
select '{{ var("direct_channel_key") }}',  'Direct (no partner)', 'direct'
union all
select '{{ var("unknown_member_key") }}', 'Unknown', 'unknown'
