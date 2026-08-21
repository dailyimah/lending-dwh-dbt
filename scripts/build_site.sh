#!/usr/bin/env bash
# Assemble the GitHub Pages site from the README, design details, diagrams and the static dbt docs.
# Run after `dbt docs generate --static`.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf site && mkdir -p site/dbt

REPO="https://github.com/dailyimah/lending-dwh-dbt"

# nav: the current page is plain text, the others are links
nav() {  # $1 = current page key: home | details
  local home='<a href="./">Overview</a>' details='<a href="design_details.html">Design details</a>'
  [ "$1" = home ]    && home='<strong>Overview</strong> (this page)'
  [ "$1" = details ] && details='<strong>Design details</strong> (this page)'
  echo "<p>${home} &nbsp;|&nbsp; ${details} &nbsp;|&nbsp; <a href=\"dbt/\">dbt docs: lineage and catalog</a> &nbsp;|&nbsp; <a href=\"${REPO}\">Repository on GitHub</a></p>"
  echo
}

# Overview = README without the repo-only header (H1, badge, live-site line); paths rewritten for the site
{
  nav home
  sed -e '/^# Fazz Data Engineer Case Study/d' \
      -e '/^\[!\[build-and-publish\]/d' \
      -e '/^\*\*Live site:\*\*/d' \
      -e 's#docs/diagrams/#diagrams/#g' \
      -e 's#docs/design_details.md#design_details.md#g' \
      -e 's#Lineage and column docs:.*$#Lineage and column docs: [dbt docs](dbt/).#' \
      README.md
} > site/index.md

{
  nav details
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
