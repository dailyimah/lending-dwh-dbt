{{ config(materialized='ephemeral') }}
/*
  int_loan_milestones - one row per loan with the FIRST time each lifecycle status
  was reached (from loan_movement history), plus the current status derived from
  history. loan.movement_status_id is kept alongside so disagreement can be tested.
*/
with mv as (
    select m.loan_id, m.moved_at, s.status_name, d.lifecycle_order
    from {{ ref('stg_loan_movement') }} m
    join {{ ref('stg_movement_status') }} s on s.movement_id = m.movement_id
    join {{ ref('dim_movement_status') }} d on d.movement_id = m.movement_id
),
pivoted as (
    select
        loan_id,
        min(case when status_name = 'requested'   then moved_at end) as requested_at,
        min(case when status_name = 'approved'    then moved_at end) as approved_at,
        min(case when status_name = 'rejected'    then moved_at end) as rejected_at,
        min(case when status_name = 'cancelled'   then moved_at end) as cancelled_at,
        min(case when status_name = 'funding'     then moved_at end) as funding_at,
        min(case when status_name = 'disbursed'   then moved_at end) as disbursed_at,
        min(case when status_name = 'repaid'      then moved_at end) as repaid_at,
        min(case when status_name = 'written_off' then moved_at end) as written_off_at,
        count(*)                                                      as movement_count
    from mv
    group by loan_id
),
latest as (
    select loan_id, status_name as current_status_name,
           -- latest by time; identical timestamps resolved by lifecycle order (defensive)
           row_number() over (partition by loan_id order by moved_at desc, lifecycle_order desc) as rn
    from mv
)
select
    p.*,
    l.current_status_name,
    coalesce(p.repaid_at, p.written_off_at, p.rejected_at, p.cancelled_at) as closed_at
from pivoted p
join latest l on l.loan_id = p.loan_id and l.rn = 1
