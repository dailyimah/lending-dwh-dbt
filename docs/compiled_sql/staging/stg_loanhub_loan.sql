
/* stg_loanhub_loan - partner channeling mapping; assumed 0..1 per loan (latest kept). */
with src as (
    select *,
           row_number() over (partition by loan_id order by updated_at desc) as rn
    from "fazz_dwh"."main_raw"."loanhub_loan"
)
select
    id                                  as loanhub_loan_id,
    loan_id,
    loan_reference_id,
    partner_id,
    cast(partner_commission_pa as numeric(28,6)) as partner_commission_pa,
    cast(created_at as timestamp)       as mapped_at,
    cast(updated_at as timestamp)       as source_updated_at
from src
where rn = 1