#!/usr/bin/env bash
# Export dbt-compiled (Jinja-free) SQL into docs/compiled_sql so reviewers who do not
# use dbt can read plain SQL. Run after `dbt compile`.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf docs/compiled_sql && mkdir -p docs/compiled_sql
for layer in staging intermediate warehouse marts; do
  mkdir -p "docs/compiled_sql/$layer"
  cp target/compiled/fazz_dwh/models/$layer/*.sql "docs/compiled_sql/$layer/"
done
mkdir -p docs/compiled_sql/tests
cp target/compiled/fazz_dwh/tests/*.sql docs/compiled_sql/tests/ 2>/dev/null || true
echo "exported: $(find docs/compiled_sql -name '*.sql' | wc -l | tr -d ' ') files"
