-- DQ: SCD2 validity intervals of one customer must be contiguous and non-overlapping.
with v as (
    select customer_id, sequence_no, valid_from, valid_to,
           lag(valid_to) over (partition by customer_id order by sequence_no) as prev_valid_to
    from {{ ref('dim_customer') }}
)
select *
from v
where prev_valid_to is not null
  and prev_valid_to <> valid_from
