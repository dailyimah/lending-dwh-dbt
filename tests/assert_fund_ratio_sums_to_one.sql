{{ config(severity='warn') }}
-- DQ: lender shares of a funded loan must sum to 1.0 (planted: one loan sums to 0.95).
select loan_id, lender_count, fund_ratio_total
from {{ ref('fact_loan') }}
where lender_count > 0
  and abs(fund_ratio_total - 1) > 0.01
