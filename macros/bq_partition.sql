{#- BigQuery partition config; none on DuckDB (dbt-duckdb reserves partition_by for its own form). -#}
{% macro bq_partition(field, granularity='day') -%}
  {%- if target.type == 'bigquery' -%}
    {{ return({'field': field, 'data_type': 'date', 'granularity': granularity}) }}
  {%- else -%}
    {{ return(none) }}
  {%- endif -%}
{%- endmacro %}
