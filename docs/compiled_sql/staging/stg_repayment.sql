
/* stg_repayment - PROPOSED source. One row per actual transfer (NOT yet allocated to installments). */
select distinct
    id                                  as repayment_id,
    transfer_id,
    loan_id,
    cast(paid_at as timestamp)          as paid_at,
    cast(paid_at as date)               as paid_date,
    cast(amount as numeric(28,6)) as paid_amount,
    lower(payment_channel)              as payment_channel
from "fazz_dwh"."main_raw"."repayment"