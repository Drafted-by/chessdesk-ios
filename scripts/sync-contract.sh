#!/usr/bin/env bash
# Copies the app API contract from the site repository (main, or the ref
# given as first argument) into contracts/. Run it when the site's API
# changes, then run the tests: ContractTests decodes an example of every
# schema the app reads, so a breaking change fails here first.
set -euo pipefail
ref="${1:-main}"
cd "$(dirname "$0")/.."
gh api "repos/Drafted-by/chessdesk/contents/apps/web/docs/api/openapi-v1.json?ref=${ref}" \
  -H "Accept: application/vnd.github.raw" > contracts/openapi-v1.json.new
mv contracts/openapi-v1.json.new contracts/openapi-v1.json
git --no-pager diff --stat -- contracts/openapi-v1.json
