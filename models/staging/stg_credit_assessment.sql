{{ config(materialized='view') }}
/* stg_credit_assessment - PROPOSED source. Point-in-time credit scores. */
select distinct
    id                                  as credit_assessment_id,
    customer_id,
    cast(assessed_at as timestamp)      as assessed_at,
    cast(credit_score as integer)       as credit_score,
    upper(grade)                        as assessed_grade
from {{ ref('credit_assessment') }}
