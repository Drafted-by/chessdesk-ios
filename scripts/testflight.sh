#!/usr/bin/env bash
# Archives the app and uploads it to App Store Connect (TestFlight).
# Usage: ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/testflight.sh <build number>
# Needs on this Mac: the App Store Connect API key in
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8, an "Apple
# Distribution" identity in a keychain, and the provisioning profile
# "ChessDesk App Store". The version is MARKETING_VERSION in project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
build="${1:?build number, e.g. 2}"
: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}"
key="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
auth=(-authenticationKeyPath "$key" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
scripts/fetch-nnue.sh
scripts/fetch-sounds.sh
xcodegen generate >/dev/null
rm -rf .build/Archive .build/Export
xcodebuild archive -project ChessDesk.xcodeproj -scheme ChessDesk -configuration Release \
  -destination "generic/platform=iOS" -archivePath .build/Archive/ChessDesk.xcarchive \
  -derivedDataPath .build/ArchiveData -allowProvisioningUpdates "${auth[@]}" \
  CURRENT_PROJECT_VERSION="$build" -quiet
cat > .build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>9ZG8RKF7RL</string>
	<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>Apple Distribution</string>
	<key>provisioningProfiles</key>
	<dict><key>app.chessdesk.ios</key><string>ChessDesk App Store</string></dict>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath .build/Archive/ChessDesk.xcarchive \
  -exportOptionsPlist .build/ExportOptions.plist -exportPath .build/Export "${auth[@]}" \
  | grep -E "Upload|EXPORT|error" || true
