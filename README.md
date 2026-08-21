# Fazz Data Engineer Case Study - Task 1: Lending Data Warehouse

[![build-and-publish](https://github.com/dailyimah/lending-dwh-dbt/actions/workflows/pages.yml/badge.svg)](https://github.com/dailyimah/lending-dwh-dbt/actions/workflows/pages.yml)
**Live site:** https://dailyimah.github.io/lending-dwh-dbt/ - landing page, [dbt docs (lineage and catalog)](https://dailyimah.github.io/lending-dwh-dbt/dbt/), design details.

Dimensional warehouse + data marts for a P2P lending business, delivered as a runnable **dbt**
project. Models are written for **BigQuery**; they run locally on **DuckDB** against synthetic
data, so the whole thing builds without credentials.

```bash
uv sync                                   # creates .venv from pyproject.toml / uv.lock
uv run dbt deps                           # installs dbt_utils
DBT_PROFILES_DIR=. uv run dbt build       # seeds -> staging -> dims -> facts -> marts -> tests
```

**5 facts - 5 conformed dimensions (customer = SCD Type 2) - 4 marts. All tests pass except two
intentional warnings that surface planted source defects.**
Full design rationale: [`docs/design_details.md`](docs/design_details.md). Lineage and column docs:
`uv run dbt docs generate && uv run dbt docs serve`.

---

## 1. Source analysis (short)

Ten table specs and an ERD were provided; **no data rows**. The specs are the source contract and
are exercised with synthetic data ([`seeds/generate_seeds.py`](https://github.com/dailyimah/lending-dwh-dbt/blob/main/seeds/generate_seeds.py), with planted defects). Staging fixes
what the specs imply: INTEGER/STRING FK mismatch, DATETIME columns without a zone, `founded` as a
free string, redundant status columns, orphaned keys.

"Repayments" and a credit score are required by the task but have no source table, so three
minimal entities are *proposed* and kept separate in [`seeds/proposed/`](https://github.com/dailyimah/lending-dwh-dbt/tree/main/seeds/proposed): `repayment_schedule`,
`repayment`, `credit_assessment`. The status vocabulary is not given either; it lives in one
mapping seed ([`seeds/reference/ref_movement_status_map.csv`](https://github.com/dailyimah/lending-dwh-dbt/blob/main/seeds/reference/ref_movement_status_map.csv)).

Full spec-vs-treatment table and the assumptions register: [`docs/design_details.md`](docs/design_details.md#1-source-analysis--assumptions).

---

## 2. Model

![star schema](docs/diagrams/02_dimensional_model.png)

Conceptual ERD: [`docs/diagrams/01_conceptual_erd.png`](docs/diagrams/01_conceptual_erd.png)
(one customer -> many loans / fundings; one loan -> many movements, fundings, installments, repayments).

| Fact | One row = | Type |
|---|---|---|
| `fact_loan` | one loan; milestones (`requested_at ... disbursed_at, closed_at`), channel, funding/insurance roll-ups, repayment totals, `outstanding_principal` | accumulating snapshot |
| `fact_repayment_schedule` | one expected installment | transactional, immutable |
| `fact_repayment` | one payment **applied to one installment** (`transfer_id` preserved) | transactional, append-only |
| `fact_funding` | one lender commitment to one loan (`fund_record` rolled up; `current_exposure_amount`) | transactional |
| `fact_loan_daily_snapshot` | one **active** loan per day through its closing day: outstanding, overdue, DPD, bucket, `is_npl_90` | periodic snapshot |

**`dim_customer` (SCD2).** `individual` union `company`; one row per version, opened whenever the
source record or the credit score changes; `customer_key = customer_id#sequence_no` (deterministic
surrogate - rebuild-safe, readable, no sequences needed on BigQuery). Facts store the version valid
when the loan was requested / the funding was made. Geography is denormalized into the dimension
(star, not snowflake). In production, with current-state-only sources, the same policy is a
`dbt snapshot` with `check_cols`.

Small dims (natural keys, no SCD): `dim_date`, `dim_loan_type`, `dim_movement_status`
(assumed vocabulary mapped from raw descriptions; lifecycle order, terminal/active flags),
`dim_partner` (+ `DIRECT` member).

Physical design on BigQuery: facts partitioned by their event date and clustered by loan /
customer via a target-aware `bq_partition` macro.

---

## 3. Data marts (built on the dims + facts; the segment mart rolls up the customer-grain mart)

| Mart | Grain | Answers |
|---|---|---|
| `mart_customer_360` | current customer | borrower metrics (volumes, outstanding, `max_dpd_ever`, on-time rate) + lender metrics (commitments, exposure); base for the two below and for lender concentration |
| `mart_credit_score_by_segment` | segment_type x segment_value | **avg credit score per segment** (entity type, role, channel, province) with realised-risk context |
| `mart_delinquency` | day x loan type x partner x grade | **delinquency rates**: outstanding by DPD bucket, delinquency rate, PAR30, NPL90, **TKB90** |
| `mart_loan_performance` | disbursement cohort x type x partner x grade x mode | **loan performance**: volumes, outcomes, collections, write-off rates, 30DPD-within-90d vintage |

---|---|---|---|---|---|
| direct | 45 | 314.9 | 0.323 | 0.161 | 0.908 |
| partner | 24 | 115.9 | 0.405 | 0.282 | 0.943 |

---

## 4. Pipeline & quality

```
seeds (sources) -> staging views -> intermediate (ephemeral) -> warehouse (dims, facts) -> marts
                   cast - tz - dedupe    customer change stream -
                   FK type fix           loan milestones - payment allocation
```

Tests run with `dbt build`: key uniqueness/not-null, relationships, accepted values (generic and
`dbt_utils`), plus singular checks - allocation is lossless, snapshot reconciles to `fact_loan`,
no join fan-out, SCD2 intervals contiguous with one current row, `fund_ratio` sums to 1 (warn),
status consistency (warn), schedule principal = loan amount, lifecycle timestamps ordered.

Production: seeds become `sources:`; the customer SCD2 runs as a `dbt snapshot`; the daily snapshot
and large facts go incremental on their date partition with delete+insert over a trailing window.

---

## 5. Decisions & limits (short)

- Payments are allocated to installments once, at load time, so DPD is identical in every report.
- Two repayment facts (schedule + payments) keep partial and multi-installment payments intact.
- The daily snapshot covers active loans only; it doubles as the base for OJK daily reporting.
- No `fact_loan_movement`; the funnel is milestone columns on `fact_loan`.
- Out of scope: lender yield (no interest ledger), rejection reasons, collections, insurance
  analytics, PII controls. Trade-offs with alternatives: [`docs/design_details.md`](https://github.com/dailyimah/lending-dwh-dbt/blob/main/docs/design_details.md) section 7.

## Layout

```
dbt_project.yml, profiles.yml      3 vars; duckdb (local) and bigquery (prod) targets
seeds/{given,proposed,reference}/  PDF tables / proposed gaps / placeholder lookups
models/{staging,intermediate,warehouse,marts}/
tests/                             singular data-quality tests
docs/                              design_details.md, diagrams/
.github/workflows/pages.yml        CI: dbt build + tests on DuckDB, dbt docs, deploy to GitHub Pages
```
