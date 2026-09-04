#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
DEVELOPER_ROOT="/Applications/Xcode.app/Contents/Developer"
PROJECT_PATH="$PROJECT_ROOT/GeminiVoiceKeyboard.xcodeproj"
DERIVED_DATA="$PROJECT_ROOT/build/DeviceDerivedData"
DEVICE_SELECTOR="${1:-${GEMINI_VOICE_DEVICE_UDID:-}}"
DEVELOPMENT_TEAM="${GEMINI_VOICE_DEVELOPMENT_TEAM:-}"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/GeminiVoice.app"

export DEVELOPER_DIR="$DEVELOPER_ROOT"

if [[ -z "$DEVICE_SELECTOR" ]]; then
  print -u2 "Usage: $0 <CoreDevice identifier or iPhone hardware UDID>"
  print -u2 "Or set GEMINI_VOICE_DEVICE_UDID to either identifier."
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -q 'Apple Development'; then
  print -u2 "No Apple Development signing identity. Finish Xcode > Settings > Apple Accounts sign-in, then rerun."
  exit 2
fi

DEVICE_DETAILS_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/gemini-voice-device.XXXXXX")"
DEVICE_DETAILS_JSON="$DEVICE_DETAILS_DIRECTORY/details.json"

cleanup_device_details() {
  if [[ -f "$DEVICE_DETAILS_JSON" ]]; then
    /bin/rm -f -- "$DEVICE_DETAILS_JSON"
  fi
  /bin/rmdir -- "$DEVICE_DETAILS_DIRECTORY" 2>/dev/null || true
}
trap cleanup_device_details EXIT

if ! xcrun devicectl device info details \
  --device "$DEVICE_SELECTOR" \
  --json-output "$DEVICE_DETAILS_JSON" \
  --quiet >/dev/null 2>&1; then
  print -u2 "CoreDevice could not resolve '$DEVICE_SELECTOR'. Use an identifier or hardware UDID reported for the iPhone."
  exit 3
fi

DDI_SERVICES_AVAILABLE="$(
  /usr/bin/plutil -extract result.deviceProperties.ddiServicesAvailable \
    raw -o - "$DEVICE_DETAILS_JSON" 2>/dev/null || true
)"
if [[ "$DDI_SERVICES_AVAILABLE" != "true" ]]; then
  print -u2 "The paired iPhone is not currently reachable by CoreDevice. Put it on the same LAN, unlock it, then rerun."
  exit 3
fi

XCODE_DEVICE_UDID="$(
  /usr/bin/plutil -extract result.hardwareProperties.udid \
    raw -o - "$DEVICE_DETAILS_JSON" 2>/dev/null || true
)"
if [[ -z "$XCODE_DEVICE_UDID" ]]; then
  print -u2 "CoreDevice did not report the iPhone hardware UDID required by xcodebuild."
  exit 3
fi

XCODE_DESTINATIONS="$(
  xcodebuild -project "$PROJECT_PATH" -scheme GeminiVoice -showdestinations 2>/dev/null || true
)"
if [[ "$XCODE_DESTINATIONS" != *"id:$XCODE_DEVICE_UDID"* ]]; then
  print -u2 "Xcode does not currently list hardware UDID $XCODE_DEVICE_UDID as a GeminiVoice destination."
  print -u2 "Unlock the iPhone and reconnect it to Xcode, then rerun."
  exit 3
fi

SIGNING_SETTINGS=(CODE_SIGN_STYLE=Automatic "CODE_SIGN_IDENTITY=Apple Development")
if [[ -n "$DEVELOPMENT_TEAM" ]]; then
  SIGNING_SETTINGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme GeminiVoice \
  -configuration Debug \
  -destination "platform=iOS,id=$XCODE_DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  "${SIGNING_SETTINGS[@]}" \
  build

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
APP_BUNDLE_ID="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$APP_PATH/Info.plist" 2>/dev/null || true
)"
if [[ -z "$APP_BUNDLE_ID" ]]; then
  print -u2 "The built app does not contain a CFBundleIdentifier; refusing to install an unknown product."
  exit 4
fi

xcrun devicectl device install app --device "$DEVICE_SELECTOR" "$APP_PATH" --timeout 120
xcrun devicectl device process launch \
  --device "$DEVICE_SELECTOR" \
  --terminate-existing \
  "$APP_BUNDLE_ID"

print "GeminiVoice installed and launched on the selected iPhone."
