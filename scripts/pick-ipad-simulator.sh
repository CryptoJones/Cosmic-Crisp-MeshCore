#!/usr/bin/env bash
# Print the UDID of an iPad simulator that xcodebuild will accept for this scheme.
# Prefers xcodebuild's own destination list (a device simctl lists can still be
# rejected if its runtime is missing for the selected Xcode); falls back to simctl.
# On failure, dumps everything it saw to stderr so CI logs are diagnosable.
set -uo pipefail
cd "$(dirname "$0")/.."

DEST=$(xcodebuild -project Cosmic-Crisp-MeshCore.xcodeproj -scheme CosmicCrisp -showdestinations 2>&1 || true)
LINE=$(grep "platform:iOS Simulator" <<<"$DEST" | grep "name:iPad" | grep -v "error:" | sort | tail -1 || true)
UDID=$(sed -n 's/.*id:\([0-9A-Fa-f-]*\).*/\1/p' <<<"$LINE")

if [ -z "$UDID" ]; then
  # Fallback: any available iPad simulator per simctl.
  UDID=$(xcrun simctl list devices available -j 2>/dev/null \
    | jq -r '[.devices[] | .[] | select(.isAvailable and (.name | test("iPad")))] | sort_by(.name) | reverse | .[0].udid // empty')
  LINE="(simctl) $(xcrun simctl list devices available 2>/dev/null | grep "$UDID" | head -1)"
fi

if [ -z "$UDID" ] || [ "$UDID" = "null" ]; then
  {
    echo "no usable iPad simulator destination"
    echo "--- xcodebuild -showdestinations said:"; echo "$DEST"
    echo "--- simctl runtimes:"; xcrun simctl list runtimes 2>&1
    echo "--- simctl devices:"; xcrun simctl list devices available 2>&1
  } >&2
  exit 1
fi
echo "picked: $LINE" >&2
echo "$UDID"
