-- DQ: on the as-of date the snapshot's outstanding principal must equal fact_loan's.
select s.loan_id, s.outstanding_principal as snapshot_outstanding, l.outstanding_principal as fact_outstanding
from {{ ref('fact_loan_daily_snapshot') }} s
join {{ ref('fact_loan') }} l on l.loan_id = s.loan_id
where s.snapshot_date = date '{{ var("as_of_date") }}'
  and l.current_status_name = 'disbursed'
  and abs(s.outstanding_principal - l.outstanding_principal) > {{ var('amount_tolerance') }}
