#!/usr/bin/env bash
# Captures the catalogue of bots as the server answers it (production, or the
# base URL given as first argument) into Fixtures/api-v1/play-bots.json: what
# the offline FixtureAPI serves and what the tests read. Asked without a
# session, so `canSaveGames` is false, as for any visitor. Nothing is written
# by hand. Run it when the roster or the engines change on the site, then run
# the tests (PlayCatalogueTests reads this file).
set -euo pipefail
base="${1:-https://chessdesk.app}"
cd "$(dirname "$0")/.."
curl -fsS -m 30 "${base}/api/v1/play/bots" | python3 -c '
import json, sys
catalogue = json.load(sys.stdin)
for key in ("tiers", "bots", "custom", "engines", "canSaveGames"):
    if key not in catalogue:
        sys.exit(f"sync-play-bots: the answer has no {key}")
json.dump(catalogue, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
' > Fixtures/api-v1/play-bots.json.new
mv Fixtures/api-v1/play-bots.json.new Fixtures/api-v1/play-bots.json
git --no-pager diff --stat -- Fixtures/api-v1/play-bots.json
