{{ config(materialized='table') }}
/* dim_movement_status - loan lifecycle statuses. Natural key: movement_id. */
select
    movement_id,
    status_name,
    case status_name
        when 'requested'   then 10
        when 'approved'    then 20
        when 'rejected'    then 25
        when 'cancelled'   then 26
        when 'funding'     then 30
        when 'disbursed'   then 40
        when 'repaid'      then 50
        when 'written_off' then 55
        else 99 end                                                   as lifecycle_order,
    status_name in ('rejected', 'cancelled', 'repaid', 'written_off') as is_terminal
from {{ ref('stg_movement_status') }}
union all
select 'UNKNOWN', 'unknown', 99, false
