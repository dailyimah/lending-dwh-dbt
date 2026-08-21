{#- Cast a string to DATE, returning NULL instead of failing on malformed values.
    DuckDB and BigQuery spell this differently, hence the dispatch. -#}
{% macro safe_cast_date(expr) -%}
  {{ return(adapter.dispatch('safe_cast_date', 'lending_dwh')(expr)) }}
{%- endmacro %}

{% macro bigquery__safe_cast_date(expr) -%}
  safe_cast({{ expr }} as date)
{%- endmacro %}

{% macro duckdb__safe_cast_date(expr) -%}
  try_cast({{ expr }} as date)
{%- endmacro %}
