{{ config(materialized='view') }}
/* stg_repayment - PROPOSED source. One row per actual transfer (NOT yet allocated to installments). */
select distinct
    id                                  as repayment_id,
    transfer_id,
    loan_id,
    cast(paid_at as timestamp)          as paid_at,
    cast({{ dbt.dateadd('hour', var('source_utc_offset_hours'), 'paid_at') }} as date) as paid_date,   -- business date in Jakarta time
    cast(amount as {{ dbt.type_numeric() }}) as paid_amount,
    lower(payment_channel)              as payment_channel
from {{ ref('repayment') }}
