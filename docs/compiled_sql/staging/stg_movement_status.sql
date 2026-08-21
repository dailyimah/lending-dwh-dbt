
/* stg_movement_status - lookup of status codes. */
select
    cast(movement_id as TEXT) as movement_id,
    lower(trim(description))            as status_name,
    cast(created_at as timestamp)       as source_created_at,
    cast(updated_at as timestamp)       as source_updated_at
from "fazz_dwh"."main_raw"."movement_status"