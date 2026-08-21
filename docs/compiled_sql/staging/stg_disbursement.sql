
/* stg_disbursement - one row per disbursement record. */
select distinct
    id                                  as disbursement_id,
    loan_id,
    bank_id,
    lower(disbursement_method)          as disbursement_method,
    lower(status)                       as disbursement_status,
    approver_id,
    escrow_id,
    cast(created_at as timestamp)       as disbursed_at,
    cast(updated_at as timestamp)       as source_updated_at
from "fazz_dwh"."main_raw"."disbursement"