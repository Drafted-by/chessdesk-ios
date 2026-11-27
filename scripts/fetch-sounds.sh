#!/usr/bin/env bash
# Downloads the two board sounds (move, capture) into the app's resources.
# They come from Lichess and are licensed to Drafted-by for ChessDesk only,
# so they are not in this repository and are not yours to reuse. Official
# builds run this; without the files the app builds and plays no sound.
set -euo pipefail
cd "$(dirname "$0")/.."
dir="ChessDesk/Resources/Sounds"
mkdir -p "$dir"
fetch() {
  local name="$1" sum="$2" target="$dir/$1"
  if [ -f "$target" ] && [ "$(shasum -a 256 "$target" | cut -d' ' -f1)" = "$sum" ]; then
    echo "$name is in place"
    return
  fi
  curl -fL --retry 3 -o "$target.part" "https://chessdesk.app/sounds/board/$name"
  if [ "$(shasum -a 256 "$target.part" | cut -d' ' -f1)" != "$sum" ]; then
    echo "checksum mismatch for $name (kept as $target.part)" >&2
    exit 1
  fi
  mv "$target.part" "$target"
  echo "fetched $name"
}
fetch move.mp3 3dd52fa3657d876cf40194d2005eddef3364e3b65bc0c508288529ae7bde8485
fetch capture.mp3 a1fb0b354091f7a78032c23135e42aa915c41120226027c20ea839d79f132f2b
