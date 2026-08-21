{{ config(materialized='view') }}
/* stg_movement_status - lookup of status codes. */
select
    cast(movement_id as {{ dbt.type_string() }}) as movement_id,
    lower(trim(description))            as status_name,
    cast(created_at as timestamp)       as source_created_at,
    cast(updated_at as timestamp)       as source_updated_at
from {{ ref('movement_status') }}
