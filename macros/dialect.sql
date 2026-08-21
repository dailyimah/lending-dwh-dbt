{#-
  Dialect helpers. Models are written for BigQuery (prod); DuckDB is used for
  local, credential-free execution. Everything that differs lives here.
-#}

{#- Naive DATETIME (local wall-clock, no tz) -> UTC TIMESTAMP.
    Assumption: naive values are Asia/Jakarta (var reporting_timezone). -#}
{% macro local_to_utc(col) -%}
  {{ return(adapter.dispatch('local_to_utc', 'fazz_dwh')(col)) }}
{%- endmacro %}

{% macro bigquery__local_to_utc(col) -%}
  timestamp(cast({{ col }} as datetime), '{{ var("reporting_timezone") }}')
{%- endmacro %}

{% macro duckdb__local_to_utc(col) -%}
  {#- nested form is independent of the session TimeZone setting -#}
  timezone('UTC', timezone('{{ var("reporting_timezone") }}', cast({{ col }} as timestamp)))
{%- endmacro %}

{% macro default__local_to_utc(col) -%}
  cast({{ col }} as timestamp)
{%- endmacro %}


{#- Safe date parse with an explicit format; returns NULL on failure. -#}
{% macro safe_parse_date(col, fmt) -%}
  {{ return(adapter.dispatch('safe_parse_date', 'fazz_dwh')(col, fmt)) }}
{%- endmacro %}

{% macro bigquery__safe_parse_date(col, fmt) -%}
  safe.parse_date('{{ fmt }}', {{ col }})
{%- endmacro %}

{% macro duckdb__safe_parse_date(col, fmt) -%}
  cast(try_strptime({{ col }}, '{{ fmt }}') as date)
{%- endmacro %}

{% macro default__safe_parse_date(col, fmt) -%}
  cast({{ col }} as date)
{%- endmacro %}


{#- Regex match predicate. -#}
{% macro regex_match(col, pattern) -%}
  {{ return(adapter.dispatch('regex_match', 'fazz_dwh')(col, pattern)) }}
{%- endmacro %}

{% macro bigquery__regex_match(col, pattern) -%}
  regexp_contains({{ col }}, r'{{ pattern }}')
{%- endmacro %}

{% macro duckdb__regex_match(col, pattern) -%}
  regexp_matches({{ col }}, '{{ pattern }}')
{%- endmacro %}

{% macro default__regex_match(col, pattern) -%}
  regexp_like({{ col }}, '{{ pattern }}')
{%- endmacro %}


{#- company.founded arrives as STRING in mixed formats (planted issue):
    'YYYY' | 'YYYY-MM-DD' | 'MM/YYYY'. Parse each; NULL if none match. -#}
{% macro parse_founded(col) -%}
  case
    when {{ regex_match(col, '^[0-9]{4}$') }}
      then {{ safe_parse_date("concat(" ~ col ~ ", '-01-01')", '%Y-%m-%d') }}
    when {{ regex_match(col, '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') }}
      then {{ safe_parse_date(col, '%Y-%m-%d') }}
    when {{ regex_match(col, '^[0-9]{2}/[0-9]{4}$') }}
      then {{ safe_parse_date("concat('01/', " ~ col ~ ")", '%d/%m/%Y') }}
    else null
  end
{%- endmacro %}


{#- Date spine between two literal dates (inclusive). -#}
{% macro date_spine(start_date, end_date) -%}
  {{ return(adapter.dispatch('date_spine', 'fazz_dwh')(start_date, end_date)) }}
{%- endmacro %}

{% macro bigquery__date_spine(start_date, end_date) -%}
  select d as date_day from unnest(generate_date_array('{{ start_date }}', '{{ end_date }}')) as d
{%- endmacro %}

{% macro duckdb__date_spine(start_date, end_date) -%}
  select cast(d as date) as date_day
  from generate_series(date '{{ start_date }}', date '{{ end_date }}', interval 1 day) as t(d)
{%- endmacro %}


{#- ISO-ish day of week: 1 = Monday ... 7 = Sunday. -#}
{% macro day_of_week(col) -%}
  {{ return(adapter.dispatch('day_of_week', 'fazz_dwh')(col)) }}
{%- endmacro %}

{% macro bigquery__day_of_week(col) -%}
  mod(extract(dayofweek from {{ col }}) + 5, 7) + 1
{%- endmacro %}

{% macro duckdb__day_of_week(col) -%}
  isodow({{ col }})
{%- endmacro %}
