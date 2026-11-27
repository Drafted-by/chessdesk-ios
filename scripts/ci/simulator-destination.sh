#!/usr/bin/env bash
set -euo pipefail

device_id="$(xcrun simctl list devices available --json \
  | jq -r '[.devices[][] | select(
      .isAvailable == true
      and (.deviceTypeIdentifier | contains(".iPhone-"))
    )][0].udid')"

[[ -n "$device_id" && "$device_id" != "null" ]] || {
  echo "No available iPhone simulator runtime" >&2
  exit 1
}

echo "platform=iOS Simulator,id=$device_id"
