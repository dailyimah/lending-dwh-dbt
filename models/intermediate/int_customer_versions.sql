{{ config(materialized='ephemeral') }}
/*
  int_customer_versions - the unified customer CHANGE STREAM.
  One row per (customer_id, event_ts) where event_ts is any moment the customer's
  source record OR credit score changed. Each row carries the customer attributes
  and credit score AS OF that moment (point-in-time join). dim_customer collapses
  this stream into SCD2 versions using the Type-2 column policy.
*/
with cust as (
    select * from {{ ref('stg_individual') }}
    union all
    select * from {{ ref('stg_company') }}
),
credit as (
    select customer_id, assessed_at as event_ts, credit_score, assessed_grade
    from {{ ref('stg_credit_assessment') }}
),
events as (
    select distinct customer_id, source_updated_at as event_ts from cust
    union
    select distinct cr.customer_id, cr.event_ts
    from credit cr
    where exists (select 1 from cust c where c.customer_id = cr.customer_id)
),
attrs as (
    select
        e.customer_id, e.event_ts,
        c.entity_type, c.customer_name, c.email, c.phone_number,
        c.country_id, c.province_id, c.city_id, c.district_id,
        c.is_borrower, c.is_lender, c.identity_card_type,
        c.founded_date, c.pic_name, c.nib_number,
        c.source_created_at, c.source_updated_at,
        row_number() over (partition by e.customer_id, e.event_ts order by c.source_updated_at desc) as rn
    from events e
    join cust c
      on c.customer_id = e.customer_id
     and c.source_updated_at <= e.event_ts
),
scores as (
    select
        e.customer_id, e.event_ts, cr.credit_score, cr.assessed_grade,
        row_number() over (partition by e.customer_id, e.event_ts order by cr.event_ts desc) as rn
    from events e
    join credit cr
      on cr.customer_id = e.customer_id
     and cr.event_ts <= e.event_ts
)
select
    a.customer_id, a.event_ts,
    a.entity_type, a.customer_name, a.email, a.phone_number,
    a.country_id, a.province_id, a.city_id, a.district_id,
    a.is_borrower, a.is_lender, a.identity_card_type,
    a.founded_date, a.pic_name, a.nib_number,
    a.source_created_at, a.source_updated_at,
    s.credit_score, s.assessed_grade
from attrs a
left join scores s
  on s.customer_id = a.customer_id and s.event_ts = a.event_ts and s.rn = 1
where a.rn = 1
