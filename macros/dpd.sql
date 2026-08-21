{#- OJK days-past-due buckets for fintech lending portfolio quality. -#}
{% macro dpd_bucket(dpd_col) -%}
  case
    when {{ dpd_col }} is null or {{ dpd_col }} < 1 then 'current'
    when {{ dpd_col }} <= 30 then '1-30'
    when {{ dpd_col }} <= 60 then '31-60'
    when {{ dpd_col }} <= 90 then '61-90'
    else '90+'
  end
{%- endmacro %}

{#- Reporting horizon. -#}
{% macro as_of_date() -%}
  cast('{{ var("as_of_date") }}' as date)
{%- endmacro %}
