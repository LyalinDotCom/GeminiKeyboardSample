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

device_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = [device for runtime, entries in json.load(sys.stdin)["devices"].items()
           if "iOS-27-" in runtime for device in entries
           if device["name"].startswith("iPhone")]
devices.sort(key=lambda device: device["state"] != "Booted")
print(devices[0]["udid"] if devices else "")
')"
if [[ -z "$device_id" ]]; then
  echo "No available iOS 27 iPhone simulator was found."
  exit 1
fi

xcodebuild \
  -project GeminiVoiceKeyboard.xcodeproj \
  -scheme GeminiVoice \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath DerivedData \
  test
