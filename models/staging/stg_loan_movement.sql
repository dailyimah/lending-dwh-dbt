{{ config(materialized='view') }}
/* stg_loan_movement - one row per status transition of a loan (history is the source of truth for status). */
select distinct
    id                                  as loan_movement_id,
    loan_id,
    cast(movement_id as {{ dbt.type_string() }}) as movement_id,
    cast(created_at as timestamp)       as moved_at,
    cast(updated_at as timestamp)       as source_updated_at
from {{ ref('loan_movement') }}
