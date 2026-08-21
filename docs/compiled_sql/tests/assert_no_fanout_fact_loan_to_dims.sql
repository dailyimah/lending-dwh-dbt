-- DQ: joining fact_loan to all its dimensions must not change the row count (no fan-out, no loss).
with base as (select count(*) as n from "fazz_dwh"."main_warehouse"."fact_loan"),
joined as (
    select count(*) as n
    from "fazz_dwh"."main_warehouse"."fact_loan" f
    join "fazz_dwh"."main_warehouse"."dim_customer"        c  on c.customer_key  = f.borrower_customer_key
    join "fazz_dwh"."main_warehouse"."dim_loan_type"       lt on lt.loan_type_id = f.loan_type_id
    join "fazz_dwh"."main_warehouse"."dim_partner"         p  on p.partner_id    = f.partner_id
    join "fazz_dwh"."main_warehouse"."dim_movement_status" ms on ms.movement_id  = f.current_movement_id
)
select base.n as fact_rows, joined.n as joined_rows
from base, joined
where base.n <> joined.n