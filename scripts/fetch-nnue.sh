#!/usr/bin/env bash
# Downloads the Stockfish network into the app's resources. The file is
# 98 MB, so it is not committed; its name is the start of its SHA-256, which
# is checked. Run once after cloning (CI runs it too).
set -euo pipefail
cd "$(dirname "$0")/.."
name="nn-1a298aa575a0.nnue"
target="ChessDesk/Resources/Engine/nn-1a298aa575a0.nnue"
mkdir -p ChessDesk/Resources/Engine
check() { [ "$(shasum -a 256 "$1" | cut -c1-12)" = "1a298aa575a0" ]; }
if [ -f "$target" ] && check "$target"; then
  echo "$name is in place"
  exit 0
fi
curl -fL --retry 3 -o "$target.part" "https://data.stockfishchess.org/nn/$name"
if ! check "$target.part"; then
  echo "checksum mismatch for $name (kept as $target.part)" >&2
  exit 1
fi
mv "$target.part" "$target"
echo "fetched $name"
