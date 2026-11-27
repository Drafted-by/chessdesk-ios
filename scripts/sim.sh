#!/usr/bin/env bash
# Builds the app, installs it on a simulator and launches it.
# Usage: scripts/sim.sh [iphone|ipad] [launch arguments…]
#   scripts/sim.sh iphone -CDRoute trainer/practical-caro-kann -CDTrainerSteps 5
#   scripts/sim.sh ipad -CDBackend local
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
kind="${1:-iphone}"; shift || true
device="ChessDesk iPhone"; [ "$kind" = "ipad" ] && device="ChessDesk iPad"
[ -d ChessDesk.xcodeproj ] || xcodegen generate >/dev/null
xcodebuild build -project ChessDesk.xcodeproj -scheme ChessDesk \
  -destination "platform=iOS Simulator,name=${device}" \
  -derivedDataPath .build/DerivedData -quiet
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl install "$device" .build/DerivedData/Build/Products/Debug-iphonesimulator/ChessDesk.app
xcrun simctl terminate "$device" app.chessdesk.ios >/dev/null 2>&1 || true
xcrun simctl launch "$device" app.chessdesk.ios "$@"
