#!/usr/bin/env bash
# Assemble the GitHub Pages site from the README, design details, diagrams and the static dbt docs.
# Run after `dbt docs generate --static`.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf site && mkdir -p site/dbt

{
  echo '**[dbt docs: lineage and catalog](dbt/)** | [Design details](design_details.md) | [Repository](https://github.com/dailyimah/lending-dwh-dbt)'
  echo
  sed -e 's#docs/diagrams/#diagrams/#g' \
      -e 's#docs/design_details.md#design_details.md#g' README.md
} > site/index.md

{
  echo '[Home](./) | **[dbt docs: lineage and catalog](dbt/)** | [Repository](https://github.com/dailyimah/lending-dwh-dbt)'
  echo
  cat docs/design_details.md
} > site/design_details.md
cp -r docs/diagrams site/diagrams
cp target/static_index.html site/dbt/index.html
cat > site/_config.yml <<'YML'
title: Lending Data Warehouse (dbt)
description: Dimensional warehouse and data marts for a P2P lending business - Fazz Data Engineer case study, Task 1
theme: jekyll-theme-primer
YML
echo "site assembled: $(find site -type f | wc -l | tr -d ' ') files"
