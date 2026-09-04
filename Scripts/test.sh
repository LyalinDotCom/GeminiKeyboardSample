#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

cd "$project_root"
xcodegen_bin="${XCODEGEN_BIN:-$(command -v xcodegen || true)}"
if [[ -n "$xcodegen_bin" ]]; then
  "$xcodegen_bin" generate
else
  echo "XcodeGen not found; using the committed Xcode project."
fi

device_id="$(xcrun simctl list devices available | sed -nE 's/^[[:space:]]*iPhone[^\(]*\(([A-F0-9-]+)\) \((Booted|Shutdown)\).*$/\1/p' | head -n 1)"
if [[ -z "$device_id" ]]; then
  echo "No available iPhone simulator was found."
  exit 1
fi

xcodebuild \
  -project GeminiVoiceKeyboard.xcodeproj \
  -scheme GeminiVoice \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath DerivedData \
  test
