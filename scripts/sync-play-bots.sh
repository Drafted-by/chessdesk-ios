#!/usr/bin/env bash
# Rebuilds Fixtures/api-v1/play-bots.json, the catalogue of bots, from the
# site's source of truth (main, or the ref given as first argument):
#   apps/web/lib/play/authed-bots.ts            the roster, its tiers, tierOf
#   apps/web/components/play/colour-step.tsx    the "build your own" opponent
#   apps/web/public/engine/maia-model-meta.json where the Maia network is served
# Run it when the roster changes on the site, then run the tests
# (PlayCatalogueTests reads this file). Nothing is written by hand.
set -euo pipefail
ref="${1:-main}"
cd "$(dirname "$0")/.."
raw() {
  gh api "repos/Drafted-by/chessdesk/contents/$1?ref=${ref}" -H "Accept: application/vnd.github.raw"
}
BOTS_TS="$(raw apps/web/lib/play/authed-bots.ts)" \
COLOUR_TSX="$(raw apps/web/components/play/colour-step.tsx)" \
PLAY_APP_TSX="$(raw apps/web/components/play/play-app.tsx)" \
MAIA_META="$(raw apps/web/public/engine/maia-model-meta.json)" \
python3 - <<'PY' > Fixtures/api-v1/play-bots.json.new
import json, os, re, sys

bots_ts = os.environ["BOTS_TS"]
colour = os.environ["COLOUR_TSX"]
play_app = os.environ["PLAY_APP_TSX"]
meta = json.loads(os.environ["MAIA_META"])

def need(match, what):
    if not match:
        sys.exit(f"sync-play-bots: could not read {what}; the site's source changed shape")
    return match

string = r'"((?:[^"\\]|\\.)*)"'
tiers = [
    {"id": m.group(1), "label": m.group(2), "blurb": m.group(3)}
    for m in re.finditer(r'\{\s*id:\s*' + string + r',\s*label:\s*' + string + r',\s*blurb:\s*' + string + r'\s*\}', bots_ts)
]
need(tiers, "BOT_TIERS")

# tierOf: `if (rating < 900) return "beginner";` ... `return "expert";`
body = need(re.search(r'export function tierOf\(rating: number\): BotTier \{(.*?)\n\}', bots_ts, re.S), "tierOf").group(1)
steps = [(int(m.group(1)), m.group(2)) for m in re.finditer(r'if \(rating < (\d+)\) return "(\w+)";', body)]
last = need(re.search(r'\n\s*return "(\w+)";\s*$', body), "tierOf's last tier").group(1)
def tier_of(rating):
    for limit, name in steps:
        if rating < limit:
            return name
    return last

bots = []
call = re.compile(
    r'\bB\(\s*' + string + r',\s*' + string + r',\s*' + string + r',\s*(\d+),\s*' + string + r',\s*' + string
    + r',\s*([0-9.]+)(?:,\s*' + string + r')?\s*\)'
)
for m in call.finditer(bots_ts.split("export const AUTHED_BOTS")[1]):
    ident, name, country, rating, tagline, first, wildness, avatar = m.groups()
    rating = int(rating)
    bots.append({
        "id": ident,
        "name": json.loads(f'"{name}"'),
        "country": json.loads(f'"{country}"'),
        "rating": rating,
        "tier": tier_of(rating),
        "avatar": avatar or f"/bots/{ident}.webp",
        "flag": f"/flags/{ident}.svg",
        "tagline": json.loads(f'"{tagline}"'),
        "firstMove": first,
        "wildness": float(wildness),
        # lib/play/gate.ts lets everyone through and the public page needs no account.
        "access": "free",
    })
need(bots, "AUTHED_BOTS")

low, high = need(re.search(r'CUSTOM_RATING_RANGE = \[(\d+), (\d+)\]', colour), "CUSTOM_RATING_RANGE").groups()
custom = {
    "name": need(re.search(r'CUSTOM_BOT_NAME = ' + string, colour), "CUSTOM_BOT_NAME").group(1),
    "avatar": need(re.search(r'CUSTOM_AVATAR = ' + string, colour), "CUSTOM_AVATAR").group(1),
    "minRating": int(low),
    "maxRating": int(high),
    "step": int(need(re.search(r'step=\{(\d+)\}', colour), "the rating slider's step").group(1)),
    "defaultRating": int(need(re.search(r'useState\((\d+)\);\s*\n\s*const \[start', colour), "the default rating").group(1)),
    "wildness": float(need(re.search(r':\s*\{\s*wildness:\s*([0-9.]+)\s*\}', play_app), "the custom bot's wildness").group(1)),
}

catalogue = {
    "tiers": tiers,
    "bots": bots,
    "custom": custom,
    "maia": {
        "model": meta["model"],
        "url": meta["url"],
        "policyName": meta["policyName"],
        "policyDim": meta["policyDim"],
    },
}
json.dump(catalogue, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
PY
mv Fixtures/api-v1/play-bots.json.new Fixtures/api-v1/play-bots.json
git --no-pager diff --stat -- Fixtures/api-v1/play-bots.json
