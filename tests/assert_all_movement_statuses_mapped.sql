{{ config(severity='warn') }}
-- DQ: every source status description must map to a canonical lifecycle stage
-- (seeds/reference/ref_movement_status_map.csv). Unmapped statuses break milestones downstream.
select movement_id, source_description
from {{ ref('dim_movement_status') }}
where status_name = 'unmapped'
