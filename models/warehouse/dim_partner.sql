{{ config(materialized='table') }}
/* dim_partner - origination channel. Natural key: partner_id. DIRECT = loan with no partner mapping. */
select
    o.partner_id,
    coalesce(r.partner_name, 'Unmapped partner') as partner_name,
    coalesce(r.channel_type, 'partner')          as channel_type
from (select distinct partner_id from {{ ref('stg_loanhub_loan') }}) o
left join {{ ref('ref_partner') }} r on r.partner_id = o.partner_id
union all select 'DIRECT',  'Direct (no partner)', 'direct'
union all select 'UNKNOWN', 'Unknown',             'unknown'
