# Design details

Appendix to the overview: what the specs implied, what was assumed, and why the model is shaped
the way it is.

## What the specs say, and how it is treated

| Spec | Treatment |
|---|---|
| `loan.movement_status_id` is INTEGER, `movement_status.movement_id` is STRING | cast in `stg_loan`; relationship test |
| `individual`, `company`, `insurance` use DATETIME (no zone); other tables TIMESTAMP | to UTC with a fixed UTC+7 offset (`source_utc_offset_hours` var) |
| `loan.movement_status_id` and `loan_movement` both describe status | history is the source of truth; disagreement flagged by `fact_loan.has_status_mismatch` (warn) |
| `company.founded` is a free STRING | `YYYY`, `YYYY-MM-DD`, `MM/YYYY` parsed; other shapes NULL |
| `fund.fund_ratio` = "ratio of funds contributed by the lender" | read as the lender's share of the loan, expected to sum to 1 (warn test) |
| `is_borrower` / `is_lender` on both `individual` and `company` | one `dim_customer` with `entity_type` and `customer_role` |
| foreign keys may be orphaned | `UNKNOWN` member in every dimension |

## Proposed source entities

The task names Repayments as a core entity and asks for a credit-score mart; neither has a source
table. Minimal shapes, kept in
[`seeds/proposed/`](https://github.com/dailyimah/lending-dwh-dbt/tree/main/seeds/proposed):

| Table | Columns | Purpose |
|---|---|---|
| `repayment_schedule` | id, loan_id, installment_no, due_date, due_principal, due_interest, due_amount | expected side of delinquency |
| `repayment` | id, loan_id, transfer_id, paid_at, amount, payment_channel | actual transfers, not pre-allocated |
| `credit_assessment` | id, customer_id, assessed_at, credit_score, grade | point-in-time score |

## Assumptions

- Status vocabulary is assumed because the spec lists no values; it is held in one seed,
  [`ref_movement_status_map.csv`](https://github.com/dailyimah/lending-dwh-dbt/blob/main/seeds/reference/ref_movement_status_map.csv),
  and unmapped descriptions surface as `unmapped` with a warn test. Change: edit the seed.
- A loan is on book from its first `disbursed` movement until a terminal movement, because the
  movement history is the only lifecycle signal. Change: the seed's `is_active_book` flag.
- Naive DATETIME is Jakarta time (UTC+7, no DST). Change: `source_utc_offset_hours`.
- Payments are allocated oldest-due-first with a proportional principal/interest split, the
  standard lending convention. Change: `int_repayment_allocation`.
- `loanhub_loan` is a 0..1 partner mapping (ERD label "maps"); no mapping means `DIRECT`.
- `lender_type` is derived from `entity_type` (company = institutional) until a master-data
  attribute exists.
- `disbursement.status`, `fund.status`, `insurance.status` are carried but not interpreted
  because their values are unknown.
- DPD buckets (1-30 / 31-60 / 61-90 / >90) are standard ageing; the 90-day line is the OJK TKB90
  metric.

## Bus matrix

| Process -> fact | dim_customer | dim_date | dim_loan_type | dim_movement_status | dim_partner |
|---|:-:|:-:|:-:|:-:|:-:|
| origination and lifecycle -> `fact_loan` | borrower | x | x | x | x |
| scheduling -> `fact_repayment_schedule` | borrower | due date | x | | x |
| collection -> `fact_repayment` | borrower | paid date | x | | x |
| funding -> `fact_funding` | **lender** | x | x | | x |
| daily position -> `fact_loan_daily_snapshot` | borrower | x | x | x | x |

`dim_customer` is in every row and plays two roles, which is why `individual` and `company` are
conformed into one dimension.

## SCD2 worked example

A borrower re-scored twice; each change opens a version and facts reference the version valid at
their event time.

| customer_key | city_id | credit_score | valid_from | valid_to | is_current |
|---|---|---|---|---|---|
| `C-101#1` | C3374 | null | 2024-11-21 | 2025-09-14 | false |
| `C-101#2` | C3374 | 584 | 2025-09-14 | 2026-03-14 | false |
| `C-101#3` | C3374 | 602 | 2026-03-14 | 9999-12-31 | true |

## Payment allocation worked example

Two installments of 500,000 due 1 Feb and 1 Mar. Payments: 500,000 on 1 Feb, 200,000 on 5 Mar,
300,000 on 15 Mar. Running totals turn both into intervals; the overlap is the allocation.

| payment (interval) | installment (interval) | allocated | days late |
|---|---|---|---|
| 1 Feb 500,000 (0 - 500,000) | #1 (0 - 500,000) | 500,000 | 0 |
| 5 Mar 200,000 (500,000 - 700,000) | #2 (500,000 - 1,000,000) | 200,000 | 4 |
| 15 Mar 300,000 (700,000 - 1,000,000) | #2 (500,000 - 1,000,000) | 300,000 | 14 |

A single transfer covering two installments yields two rows the same way; `transfer_id` links them.

## Trade-offs

| Chose | Rejected | Why |
|---|---|---|
| deterministic key `customer_id#sequence_no` | opaque integer surrogate | same input gives the same key, so a rebuild never breaks fact FKs |
| allocation at load time | raw transfers, allocate per query | one DPD definition everywhere |
| schedule + payments as two facts | one installment row updated in place | partial and merged payments keep their detail |
| snapshot of active loans only | every loan every day | size tracks the live book |
| milestone columns on `fact_loan` | `fact_loan_movement` | funnel questions need first-reached timestamps only |
| metrics in marts | metrics in `dim_customer` | otherwise every repayment opens a customer version |

## Out of scope

Lender yield (no interest data), rejection reasons, collections workflow, insurance beyond a flag,
PII controls (BigQuery policy tags in production). BigQuery partitioning is declared via
`bq_partition` but has not been executed on BigQuery.
