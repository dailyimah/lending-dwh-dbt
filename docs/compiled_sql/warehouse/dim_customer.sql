
/*
  dim_customer - SCD Type 2. Grain: one row per customer VERSION.
  Key: customer_key = customer_id#sequence_no (deterministic surrogate).

  SCD policy (the "check_cols" equivalent, implemented explicitly):
    Type 2 (new version):  customer_role, is_borrower, is_lender, identity_card_type,
                           country_id, province_id, city_id, district_id, credit_score
    Type 1 (overwrite):    customer_name, email, phone_number, founded_date, pic_name, nib_number
  Sources already carry history (CDC-style), so versions are derived here from the
  change stream; with current-state-only sources the same policy would run as a
  dbt snapshot (strategy: check) - see README.
*/
with  __dbt__cte__int_customer_versions as (

/*
  int_customer_versions - the unified customer CHANGE STREAM.
  One row per (customer_id, event_ts) where event_ts is any moment the customer's
  source record OR credit score changed. Each row carries the customer attributes
  and credit score AS OF that moment (point-in-time join). dim_customer collapses
  this stream into SCD2 versions using the Type-2 column policy.
*/
with cust as (
    select * from "fazz_dwh"."main_staging"."stg_individual"
    union all
    select * from "fazz_dwh"."main_staging"."stg_company"
),
credit as (
    select customer_id, assessed_at as event_ts, credit_score, assessed_grade
    from "fazz_dwh"."main_staging"."stg_credit_assessment"
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
), v as (
    select
        *,
        case when is_borrower and is_lender then 'both'
             when is_borrower then 'borrower'
             when is_lender   then 'lender'
             else 'none' end as customer_role
    from __dbt__cte__int_customer_versions
),
hashed as (
    select
        *,
        md5(cast(coalesce(customer_role,'') || '|' || coalesce(cast(is_borrower as TEXT),'') || '|' || coalesce(cast(is_lender as TEXT),'') || '|' || coalesce(identity_card_type,'') || '|' || coalesce(country_id,'') || '|' || coalesce(province_id,'') || '|' || coalesce(city_id,'') || '|' || coalesce(district_id,'') || '|' || coalesce(cast(credit_score as TEXT),'') as TEXT)) as type2_hash
    from v
),
flagged as (
    select
        *,
        case when lag(type2_hash) over (partition by customer_id order by event_ts) is distinct from type2_hash
             then 1 else 0 end as is_type2_change
    from hashed
),
grouped as (
    select
        *,
        sum(is_type2_change) over (partition by customer_id order by event_ts
                                   rows between unbounded preceding and current row) as version_grp
    from flagged
),
-- latest event within each version group supplies the (Type-1) current values;
-- the earliest event supplies valid_from.
collapsed as (
    select
        *,
        min(event_ts) over (partition by customer_id, version_grp) as valid_from,
        row_number() over (partition by customer_id, version_grp order by event_ts desc) as rn_in_grp
    from grouped
),
versions as (
    select
        customer_id,
        row_number() over (partition by customer_id order by valid_from)            as sequence_no,
        valid_from,
        lead(valid_from) over (partition by customer_id order by valid_from)        as next_valid_from,
        entity_type, customer_name, email, phone_number,
        country_id, province_id, city_id, district_id,
        is_borrower, is_lender, customer_role, identity_card_type,
        credit_score, assessed_grade,
        founded_date, pic_name, nib_number,
        source_created_at, source_updated_at
    from collapsed
    where rn_in_grp = 1
),
-- acquisition channel = channel of the customer's FIRST loan
first_loan as (
    select
        l.borrower_customer_id as customer_id,
        case when lh.loan_id is not null then 'partner' else 'direct' end as origination_channel,
        row_number() over (partition by l.borrower_customer_id order by l.requested_at, l.loan_id) as rn
    from "fazz_dwh"."main_staging"."stg_loan" l
    left join "fazz_dwh"."main_staging"."stg_loanhub_loan" lh on lh.loan_id = l.loan_id
),
final as (
    select
        v.customer_id || '#' || cast(v.sequence_no as TEXT) as customer_key,
        v.customer_id,
        v.sequence_no,
        v.entity_type,
        v.customer_name,
        v.email,
        v.phone_number,
        v.country_id, v.province_id, v.city_id, v.district_id,
        v.is_borrower,
        v.is_lender,
        v.customer_role,
        case when v.is_lender and v.entity_type = 'company'    then 'institutional'
             when v.is_lender and v.entity_type = 'individual' then 'retail'
             else null end                                   as lender_type,
        fl.origination_channel,
        v.identity_card_type,
        v.credit_score,
        v.assessed_grade                                     as credit_grade,
        v.founded_date,
        v.pic_name,
        v.nib_number,
        v.source_created_at,
        v.source_updated_at,
        v.valid_from,
        coalesce(v.next_valid_from, cast('9999-12-31' as timestamp)) as valid_to,
        v.next_valid_from is null                            as is_current
    from versions v
    left join first_loan fl on fl.customer_id = v.customer_id and fl.rn = 1
)
select * from final

union all

-- member for orphaned / unknown foreign keys
select
    'UNKNOWN#1', 'UNKNOWN', 1, 'unknown',
    'Unknown customer', null, null,
    null, null, null, null,
    false, false, 'none', null, null, null,
    null, null, null, null, null,
    cast('1900-01-01' as timestamp), cast('1900-01-01' as timestamp),
    cast('1900-01-01' as timestamp), cast('9999-12-31' as timestamp), true