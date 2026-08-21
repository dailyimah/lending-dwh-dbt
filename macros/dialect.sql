{#-
  Dialect helpers. Models are written for BigQuery (prod); DuckDB runs them locally
  without credentials. Only the expressions that differ between the two live here.
-#}

{#- Naive DATETIME (local wall-clock, no tz) -> UTC TIMESTAMP. -#}
{% macro local_to_utc(col) -%}
  {{ return(adapter.dispatch('local_to_utc', 'fazz_dwh')(col)) }}
{%- endmacro %}

{% macro bigquery__local_to_utc(col) -%}
  timestamp(cast({{ col }} as datetime), '{{ var("reporting_timezone") }}')
{%- endmacro %}

{% macro duckdb__local_to_utc(col) -%}
  timezone('UTC', timezone('{{ var("reporting_timezone") }}', cast({{ col }} as timestamp)))
{%- endmacro %}


{#- company.founded arrives as STRING in mixed formats: 'YYYY' | 'YYYY-MM-DD' | 'MM/YYYY'. -#}
{% macro parse_founded(col) -%}
  {{ return(adapter.dispatch('parse_founded', 'fazz_dwh')(col)) }}
{%- endmacro %}

{% macro bigquery__parse_founded(col) -%}
  coalesce(
    safe.parse_date('%Y-%m-%d', {{ col }}),
    safe.parse_date('%m/%Y',    {{ col }}),
    safe.parse_date('%Y',       {{ col }})
  )
{%- endmacro %}

{% macro duckdb__parse_founded(col) -%}
  cast(try_strptime({{ col }}, ['%Y-%m-%d', '%m/%Y', '%Y']) as date)
{%- endmacro %}


{#- BigQuery partition config; none elsewhere (dbt-duckdb reserves partition_by for its own form). -#}
{% macro bq_partition(field, granularity='day') -%}
  {%- if target.type == 'bigquery' -%}
    {{ return({'field': field, 'data_type': 'date', 'granularity': granularity}) }}
  {%- else -%}
    {{ return(none) }}
  {%- endif -%}
{%- endmacro %}
