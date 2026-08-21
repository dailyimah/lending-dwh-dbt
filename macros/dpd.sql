{#- DPD bucket from var dpd_bucket_edges (OJK convention: current | 1-30 | 31-60 | 61-90 | >90). -#}
{% macro dpd_bucket(dpd_col) -%}
{%- set edges = var('dpd_bucket_edges') -%}
case
  when {{ dpd_col }} is null or {{ dpd_col }} < {{ edges[0] }} then 'current'
{%- for i in range(edges | length - 1) %}
  when {{ dpd_col }} < {{ edges[i+1] }} then '{{ edges[i] }}-{{ edges[i+1] - 1 }}'
{%- endfor %}
  else '{{ edges[-1] - 1 }}+'
end
{%- endmacro %}

{#- Bucket ordering for sorting in marts. -#}
{% macro dpd_bucket_order(dpd_col) -%}
{%- set edges = var('dpd_bucket_edges') -%}
case
  when {{ dpd_col }} is null or {{ dpd_col }} < {{ edges[0] }} then 0
{%- for i in range(edges | length - 1) %}
  when {{ dpd_col }} < {{ edges[i+1] }} then {{ i + 1 }}
{%- endfor %}
  else {{ edges | length }}
end
{%- endmacro %}

{#- Horizon date for snapshot/current-state calculations. -#}
{% macro as_of_date() -%}
  cast('{{ var("as_of_date") }}' as date)
{%- endmacro %}
