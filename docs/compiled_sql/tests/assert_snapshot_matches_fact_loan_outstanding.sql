-- DQ: on the as-of date the snapshot's outstanding principal must equal fact_loan's.
select s.loan_id, s.outstanding_principal as snapshot_outstanding, l.outstanding_principal as fact_outstanding
from "fazz_dwh"."main_warehouse"."fact_loan_daily_snapshot" s
join "fazz_dwh"."main_warehouse"."fact_loan" l on l.loan_id = s.loan_id
where s.snapshot_date = cast('2026-08-21' as date)
  and l.current_status_name = 'disbursed'
  and abs(s.outstanding_principal - l.outstanding_principal) > 1