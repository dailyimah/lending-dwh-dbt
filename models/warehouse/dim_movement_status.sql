{{ config(materialized='table') }}
/*
  dim_movement_status - loan lifecycle statuses. Natural key: movement_id.
  The spec does not enumerate status descriptions, so raw descriptions are mapped to an assumed
  canonical vocabulary (seeds/reference/ref_movement_status_map.csv). Unmapped -> 'unmapped'.
*/
select
    s.movement_id,
    s.status_name                               as source_description,
    coalesce(m.lifecycle_stage, 'unmapped')     as status_name,
    coalesce(m.lifecycle_order, 99)             as lifecycle_order,
    coalesce(m.is_terminal, false)              as is_terminal,
    coalesce(m.is_active_book, false)           as is_active_book
from {{ ref('stg_movement_status') }} s
left join {{ ref('ref_movement_status_map') }} m on m.description_raw = s.status_name
union all
select 'UNKNOWN', 'unknown', 'unknown', 99, false, false
