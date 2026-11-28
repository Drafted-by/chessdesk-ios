#!/bin/sh
# Renders the icon candidates, their appearances and their contact sheets into design/icon/.
set -eu
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p .build/icon
xcrun swiftc -O -parse-as-library -o .build/icon/render design/icon/render.swift ChessDesk/UI/SVGPath.swift
.build/icon/render design/icon
